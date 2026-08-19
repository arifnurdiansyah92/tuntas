# == Schema Information
#
# Table name: captain_custom_tools
#
#  id                :bigint           not null, primary key
#  auth_config       :jsonb
#  auth_type         :string           default("none")
#  description       :text
#  enabled           :boolean          default(TRUE), not null
#  endpoint_url      :text             not null
#  http_method       :string           default("GET"), not null
#  param_schema      :jsonb
#  request_template  :text
#  response_template :text
#  slug              :string           not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
class Captain::CustomTool < ApplicationRecord
  include Captain::Toolable

  self.table_name = 'captain_custom_tools'

  SLUG_PREFIX = 'custom_'.freeze
  PARAM_SCHEMA_KEYS = %w[name type description required].freeze
  PARAM_SCHEMA_REQUIRED_KEYS = %w[name type description].freeze

  belongs_to :account

  enum :http_method, { 'GET' => 'GET', 'POST' => 'POST' }
  enum :auth_type, { 'none' => 'none', 'bearer' => 'bearer', 'basic' => 'basic', 'api_key' => 'api_key' }, prefix: :auth

  validates :title, presence: true
  validates :endpoint_url, presence: true
  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validate :validate_param_schema

  before_validation :generate_slug, on: :create

  scope :enabled, -> { where(enabled: true) }

  private

  def generate_slug
    return if slug.present?
    return if title.blank?

    base_slug = "#{SLUG_PREFIX}#{title.parameterize(separator: '_')}"
    self.slug = self.class.exists?(account_id: account_id, slug: base_slug) ? "#{base_slug}_#{random_suffix}" : base_slug
  end

  def random_suffix
    SecureRandom.alphanumeric(6).downcase
  end

  def validate_param_schema
    return if param_schema.blank?

    return if param_schema.is_a?(Array) && param_schema.all? { |entry| valid_param_entry?(entry) }

    errors.add(:param_schema, 'entries must define name, type, and description only')
  end

  def valid_param_entry?(entry)
    return false unless entry.is_a?(Hash)

    keys = entry.keys.map(&:to_s)
    (keys - PARAM_SCHEMA_KEYS).empty? && (PARAM_SCHEMA_REQUIRED_KEYS - keys).empty?
  end
end
