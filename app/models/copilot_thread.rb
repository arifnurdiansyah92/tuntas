# == Schema Information
#
# Table name: copilot_threads
#
#  id           :bigint           not null, primary key
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  assistant_id :integer
#  user_id      :bigint           not null
#
class CopilotThread < ApplicationRecord
  belongs_to :user
  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant', inverse_of: :copilot_threads
  has_many :copilot_messages, dependent: :destroy_async

  validates :title, presence: true

  def push_event_data
    {
      id: id,
      title: title,
      created_at: created_at.to_i,
      user: user.push_event_data,
      account_id: account_id
    }
  end

  def previous_history
    copilot_messages.where(message_type: [:user, :assistant]).order(:created_at).map do |copilot_message|
      { role: copilot_message.message_type, content: copilot_message.message['content'] }
    end
  end
end
