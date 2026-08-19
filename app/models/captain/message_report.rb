# == Schema Information
#
# Table name: captain_message_reports
#
#  id              :bigint           not null, primary key
#  description     :text
#  report_reason   :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  message_id      :bigint           not null
#  user_id         :bigint           not null
#
class Captain::MessageReport < ApplicationRecord
  self.table_name = 'captain_message_reports'

  REPORT_REASONS = %w[incorrect_information incomplete_information inappropriate_response outdated_information other].freeze

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :message
  belongs_to :user

  validates :report_reason, presence: true, inclusion: { in: REPORT_REASONS }

  before_validation :ensure_message_context

  private

  def ensure_message_context
    self.account ||= message&.account
    self.conversation ||= message&.conversation
  end
end
