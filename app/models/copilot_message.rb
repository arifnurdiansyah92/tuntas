# == Schema Information
#
# Table name: copilot_messages
#
#  id                :bigint           not null, primary key
#  message           :jsonb            not null
#  message_type      :integer          default("user")
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  copilot_thread_id :bigint           not null
#
class CopilotMessage < ApplicationRecord
  include Events::Types

  belongs_to :copilot_thread
  belongs_to :account

  enum :message_type, { user: 0, assistant: 1, assistant_thinking: 2 }

  validates :message_type, presence: true
  validates :message, presence: true

  before_validation :ensure_account
  after_create :broadcast_message

  def push_event_data
    {
      id: id,
      message: message,
      message_type: message_type,
      created_at: created_at.to_i,
      copilot_thread: copilot_thread.push_event_data
    }
  end

  private

  def ensure_account
    self.account ||= copilot_thread&.account
  end

  def broadcast_message
    Rails.configuration.dispatcher.dispatch(COPILOT_MESSAGE_CREATED, Time.zone.now, copilot_message: self)
  end
end
