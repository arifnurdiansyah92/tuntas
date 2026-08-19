# == Schema Information
#
# Table name: agent_sessions
#
#  id                 :bigint           not null, primary key
#  cited_document_ids :jsonb
#  credits_consumed   :float
#  document_ids       :jsonb
#  faq_ids            :jsonb
#  llm_model          :string
#  run_context        :jsonb
#  scenario_ids       :jsonb
#  session_type       :integer          not null
#  used_faq_ids       :jsonb
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  assistant_id       :bigint           not null
#  result_id          :bigint
#  result_type        :string
#  subject_id         :bigint           not null
#  subject_type       :string           not null
#  user_id            :bigint
#
class Captain::AgentSession < ApplicationRecord
  self.table_name = 'agent_sessions'

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant', inverse_of: :agent_sessions
  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true
  belongs_to :result, polymorphic: true, optional: true

  enum :session_type, { assistant: 0, copilot: 1 }, prefix: :session

  SUBJECT_TYPES_BY_SESSION = { 'assistant' => 'Conversation', 'copilot' => 'CopilotThread' }.freeze

  before_validation :ensure_account_from_assistant
  validate :validate_subject
  validate :validate_result_account

  private

  def ensure_account_from_assistant
    self.account = assistant.account if assistant.present?
  end

  def validate_subject
    expected_type = SUBJECT_TYPES_BY_SESSION[session_type]
    errors.add(:subject_type, 'does not match the session type') if expected_type.present? && subject_type != expected_type

    resolved_subject = subject
    errors.add(:subject, 'must belong to the same account') if resolved_subject.respond_to?(:account_id) && resolved_subject.account_id != account_id
  rescue NameError
    errors.add(:subject, 'is invalid')
  end

  def validate_result_account
    return if result_id.blank?

    resolved_result = result
    if resolved_result.blank?
      errors.add(:result, 'must exist')
    elsif resolved_result.respond_to?(:account_id) && resolved_result.account_id != account_id
      errors.add(:result, 'must belong to the same account')
    end
  end
end
