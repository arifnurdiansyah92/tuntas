# == Schema Information
#
# Table name: captain_scenarios
#
#  id           :bigint           not null, primary key
#  description  :text
#  enabled      :boolean          default(TRUE), not null
#  instruction  :text
#  title        :string
#  tools        :jsonb
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  assistant_id :bigint           not null
#
class Captain::Scenario < ApplicationRecord
  include Concerns::CaptainToolsHelpers
  include Concerns::Agentable

  self.table_name = 'captain_scenarios'

  HANDOFF_KEY_BUDGET = 60 - 'handoff_to_'.length

  belongs_to :assistant, class_name: 'Captain::Assistant', inverse_of: :scenarios
  belongs_to :account

  validates :title, presence: true
  validates :description, presence: true
  validates :instruction, presence: true
  validates :assistant_id, presence: true
  validates :account_id, presence: true
  validate :validate_instruction_tools

  before_save :resolve_tool_references

  scope :enabled, -> { where(enabled: true) }

  def self.built_in_agent_tools
    [
      Captain::Tools::AddContactNoteTool, Captain::Tools::AddPrivateNoteTool,
      Captain::Tools::AddLabelToConversationTool, Captain::Tools::UpdatePriorityTool,
      Captain::Tools::ResolveConversationTool
    ].map do |tool_class|
      tool_id = tool_class.name.demodulize.delete_suffix('Tool').underscore
      { id: tool_id, title: tool_id.humanize, description: tool_class.description }
    end
  end

  def self.built_in_tool_ids
    built_in_agent_tools.pluck(:id)
  end

  def handoff_key
    identifier = persisted? ? id.to_s : 'draft'
    slug_budget = HANDOFF_KEY_BUDGET - "scenario_#{identifier}__agent".length
    slug = title.to_s.parameterize(separator: '_').first([slug_budget, 0].max).chomp('_')
    "scenario_#{identifier}_#{slug}_agent"
  end

  private

  def agent_name
    handoff_key
  end

  def prompt_context
    {
      title: title,
      description: description,
      instruction: instruction,
      assistant_name: assistant.name
    }
  end

  def template_name
    'captain/scenario'
  end

  def resolve_tool_references
    tool_ids = extract_tool_ids_from_text(instruction)
    self.tools = tool_ids.presence
  end

  def validate_instruction_tools
    return if instruction.blank?

    referenced_ids = extract_tool_ids_from_text(instruction)
    invalid_ids = referenced_ids - available_tool_ids
    errors.add(:instruction, "contains invalid tools: #{invalid_ids.join(', ')}") if invalid_ids.any?
  end

  def available_tool_ids
    self.class.built_in_tool_ids + account.captain_custom_tools.enabled.pluck(:slug)
  end

  def resolved_tools
    Array(tools).filter_map do |tool_id|
      if tool_id.start_with?(Captain::CustomTool::SLUG_PREFIX)
        account.captain_custom_tools.enabled.find_by(slug: tool_id)&.to_tool_metadata
      else
        self.class.built_in_agent_tools.find { |tool| tool[:id] == tool_id }
      end
    end
  end

  def resolve_tool_instance(tool_metadata)
    if tool_metadata[:custom]
      account.captain_custom_tools.enabled.find_by(slug: tool_metadata[:id])&.tool(assistant)
    else
      self.class.resolve_tool_class(tool_metadata[:id])&.new(assistant)
    end
  end

  def agent_tools
    resolved_tools.filter_map { |tool_metadata| resolve_tool_instance(tool_metadata) }
  end
end
