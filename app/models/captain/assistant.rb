# == Schema Information
#
# Table name: captain_assistants
#
#  id                  :bigint           not null, primary key
#  config              :jsonb            not null
#  description         :text
#  guardrails          :jsonb
#  name                :string           not null
#  response_guidelines :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
class Captain::Assistant < ApplicationRecord
  include Concerns::Agentable

  self.table_name = 'captain_assistants'

  CITATION_SOURCES_STATE_KEY = :captain_citation_sources
  RESPONSE_WINDOWS = %w[always business_hours outside_business_hours].freeze
  AUTO_RESOLVE_MODES = %w[legacy disabled auto].freeze
  AUTO_RESOLVE_STEP_MINUTES = 5
  DEFAULT_INACTIVITY_THRESHOLD_MINUTES = 60
  GROUP_OPERATORS = %w[and or].freeze
  VALUELESS_OPERATORS = %w[is_present is_not_present].freeze
  STANDARD_AUDIENCE_ATTRIBUTES = {
    'country_code' => %w[equal_to not_equal_to],
    'city' => %w[equal_to not_equal_to],
    'email' => %w[equal_to not_equal_to contains does_not_contain],
    'phone_number' => %w[equal_to not_equal_to contains does_not_contain],
    'blocked' => %w[equal_to not_equal_to]
  }.freeze
  CUSTOM_ATTRIBUTE_OPERATORS = %w[equal_to not_equal_to contains does_not_contain is_present is_not_present].freeze

  belongs_to :account
  has_many :documents, class_name: 'Captain::Document', dependent: :destroy_async, inverse_of: :assistant
  has_many :responses, class_name: 'Captain::AssistantResponse', dependent: :destroy_async, inverse_of: :assistant
  has_many :scenarios, class_name: 'Captain::Scenario', dependent: :destroy_async, inverse_of: :assistant
  has_many :captain_inboxes, class_name: 'CaptainInbox', foreign_key: :captain_assistant_id, dependent: :destroy_async,
                             inverse_of: :captain_assistant
  has_many :inboxes, through: :captain_inboxes
  has_many :copilot_threads, dependent: :destroy_async, inverse_of: :assistant
  has_many :agent_sessions, class_name: 'Captain::AgentSession', dependent: :destroy_async, inverse_of: :assistant

  validates :name, presence: true
  validates :description, presence: true
  validate :validate_auto_resolve_after
  validate :validate_auto_resolve_mode
  validate :validate_response_window
  validate :validate_audience
  before_validation :round_auto_resolve_after

  def auto_resolve_after
    return @auto_resolve_after if defined?(@auto_resolve_after)

    config['auto_resolve_after']
  end

  def auto_resolve_after=(value)
    @auto_resolve_after = value
    config['auto_resolve_after'] = value
  end

  def auto_resolve_mode
    config['auto_resolve_mode'].presence || account.captain_auto_resolve_mode
  end

  def auto_resolve_mode=(value)
    config['auto_resolve_mode'] = value
  end

  def inactivity_threshold_minutes
    return DEFAULT_INACTIVITY_THRESHOLD_MINUTES unless account.feature_enabled?('captain_integration_v2')

    auto_resolve_after.presence || DEFAULT_INACTIVITY_THRESHOLD_MINUTES
  end

  def send_inactivity_resolution_message?
    return true unless account.feature_enabled?('captain_integration_v2')

    config.fetch('send_inactivity_resolution_message', true)
  end

  def send_inactivity_resolution_message=(value)
    config['send_inactivity_resolution_message'] = value
  end

  def responds_to_audience?(contact, conversation)
    audience = config['audience']
    return true if audience.blank?

    evaluate_audience_node(audience.deep_stringify_keys, contact, conversation)
  end

  def push_event_data
    { id: id, name: name, type: 'captain_assistant' }
  end

  def available_name
    name
  end

  def avatar_url
    nil
  end

  def available_now?(conversation)
    window = config['response_window']
    return true if window.blank? || window == 'always'

    inbox = conversation.inbox
    return true unless inbox.working_hours_enabled?

    window == 'business_hours' ? !inbox.out_of_office? : inbox.out_of_office?
  end

  private

  def agent_name
    name
  end

  def prompt_context
    {
      name: name,
      description: description,
      response_guidelines: response_guidelines || [],
      guardrails: guardrails || [],
      citation_enabled: config['feature_citation'].present?,
      scenarios: scenarios.enabled.map do |scenario|
        { title: scenario.title, description: scenario.description, key: scenario.handoff_key }
      end
    }
  end

  def agent_tools
    tools = [Captain::Tools::FaqLookupTool.new(self), Captain::Tools::HandoffTool.new(self)]
    tools + account.captain_custom_tools.enabled.map { |custom_tool| custom_tool.tool(self) }
  end

  def round_auto_resolve_after
    value = auto_resolve_after
    return if value.blank?
    return unless value.is_a?(Numeric) && (value % 1).zero?
    return if value < AUTO_RESOLVE_STEP_MINUTES

    self.auto_resolve_after = ((value.to_f / AUTO_RESOLVE_STEP_MINUTES).round * AUTO_RESOLVE_STEP_MINUTES)
  end

  def validate_auto_resolve_after
    value = auto_resolve_after
    return if value.blank?

    errors.add(:auto_resolve_after, 'must be a whole number of minutes') unless value.is_a?(Numeric) && (value % 1).zero?
    return unless value.is_a?(Numeric) && value < AUTO_RESOLVE_STEP_MINUTES

    errors.add(:auto_resolve_after,
               "must be at least #{AUTO_RESOLVE_STEP_MINUTES} minutes")
  end

  def validate_auto_resolve_mode
    mode = config['auto_resolve_mode']
    return if mode.blank?

    errors.add(:auto_resolve_mode, 'is not supported') unless AUTO_RESOLVE_MODES.include?(mode)
  end

  def validate_response_window
    window = config['response_window']
    return if window.blank?

    errors.add(:config, 'invalid response_window') unless RESPONSE_WINDOWS.include?(window)
  end

  def validate_audience
    audience = config['audience']
    return if audience.blank?

    unless audience.is_a?(Hash)
      errors.add(:config, 'audience must be a valid condition tree')
      return
    end

    errors.add(:config, 'audience must be a valid condition tree') unless valid_audience_node?(audience.deep_stringify_keys)
  end

  def valid_audience_node?(node, depth = 0)
    return false unless node.is_a?(Hash)
    return valid_audience_group?(node, depth) if node.key?('operator') || node.key?('conditions')

    valid_audience_leaf?(node)
  end

  def valid_audience_group?(node, depth)
    return false if depth > 1
    return false unless GROUP_OPERATORS.include?(node['operator'])

    conditions = node['conditions']
    return false unless conditions.is_a?(Array) && conditions.any?

    conditions.all? { |child| valid_audience_node?(child, depth + 1) }
  end

  def valid_audience_leaf?(leaf)
    attribute_key = leaf['attribute_key']
    operator = leaf['filter_operator']
    return false if attribute_key.blank? || operator.blank?

    allowed_operators = operators_for_attribute(attribute_key)
    return false if allowed_operators.blank?
    return false unless allowed_operators.include?(operator)
    return false if VALUELESS_OPERATORS.exclude?(operator) && Array(leaf['values']).empty?

    true
  end

  def operators_for_attribute(attribute_key)
    return STANDARD_AUDIENCE_ATTRIBUTES[attribute_key] if STANDARD_AUDIENCE_ATTRIBUTES.key?(attribute_key)

    definition = account.custom_attribute_definitions.where(attribute_model: 'contact_attribute').find_by(attribute_key: attribute_key)
    return if definition.blank?

    CUSTOM_ATTRIBUTE_OPERATORS
  end

  def evaluate_audience_node(node, contact, conversation)
    if node.key?('operator') || node.key?('conditions')
      results = Array(node['conditions']).map { |child| evaluate_audience_node(child, contact, conversation) }
      node['operator'] == 'or' ? results.any? : results.all?
    else
      evaluate_audience_leaf(node, contact)
    end
  end

  OPERATOR_PREDICATES = {
    'equal_to' => ->(value, values) { values.include?(value.to_s) },
    'not_equal_to' => ->(value, values) { values.exclude?(value.to_s) },
    'contains' => ->(value, values) { values.any? { |candidate| value.to_s.downcase.include?(candidate.downcase) } },
    'does_not_contain' => ->(value, values) { values.none? { |candidate| value.to_s.downcase.include?(candidate.downcase) } },
    'is_present' => ->(value, _values) { value.present? },
    'is_not_present' => ->(value, _values) { value.blank? }
  }.freeze

  def evaluate_audience_leaf(leaf, contact)
    predicate = OPERATOR_PREDICATES[leaf['filter_operator']]
    return false if predicate.blank?

    value = contact_attribute_value(contact, leaf['attribute_key'])
    predicate.call(value, Array(leaf['values']).map(&:to_s))
  end

  def contact_attribute_value(contact, attribute_key)
    if STANDARD_AUDIENCE_ATTRIBUTES.key?(attribute_key) && contact.respond_to?(attribute_key)
      value = contact.public_send(attribute_key)
      return value unless value.nil?
    end

    contact.additional_attributes&.dig(attribute_key) || contact.custom_attributes&.dig(attribute_key)
  end
end
