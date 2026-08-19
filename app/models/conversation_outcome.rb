# == Schema Information
#
# Table name: conversation_outcomes
#
#  id                      :bigint           not null, primary key
#  captain_reply_count     :integer          default(0), not null
#  csat_rating             :integer
#  csat_received_at        :datetime
#  ended_at                :datetime
#  episode_trigger         :string           default("initial"), not null
#  first_captain_reply_at  :datetime
#  first_human_reply_at    :datetime
#  handoff_at              :datetime
#  handoff_reason_category :string
#  last_captain_reply_at   :datetime
#  resolved_at             :datetime
#  started_at              :datetime         not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  assistant_id            :bigint           not null
#  conversation_id         :bigint           not null
#  inbox_id                :bigint           not null
#
class ConversationOutcome < ApplicationRecord
  HANDOFF_REASON_CATEGORIES = %w[customer_request unsupported_request missing_information missing_knowledge policy_restriction escalation
                                 pending_clarification tool_failure usage_limit other].freeze
  EPISODE_TRIGGERS = %w[initial reopen].freeze

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :inbox

  enum :handoff_reason_category, HANDOFF_REASON_CATEGORIES.index_by(&:itself), prefix: :handoff_reason
  enum :episode_trigger, EPISODE_TRIGGERS.index_by(&:itself), prefix: :trigger

  validates :started_at, presence: true, uniqueness: { scope: [:account_id, :conversation_id] }
  validate :validate_account_consistency

  private

  def validate_account_consistency
    errors.add(:assistant, 'must belong to the same account') if assistant.present? && assistant.account_id != account_id
    errors.add(:conversation, 'must belong to the same account') if conversation.present? && conversation.account_id != account_id
    errors.add(:inbox, 'must belong to the same account') if inbox.present? && inbox.account_id != account_id
  end
end
