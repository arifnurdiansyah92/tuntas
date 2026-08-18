# == Schema Information
#
# Table name: sla_events
#
#  id              :bigint           not null, primary key
#  event_type      :integer
#  meta            :jsonb
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  applied_sla_id  :bigint           not null
#  conversation_id :bigint           not null
#  inbox_id        :bigint           not null
#  sla_policy_id   :bigint           not null
#
class SlaEvent < ApplicationRecord
  NOTIFICATION_TYPES = {
    'frt' => 'sla_missed_first_response',
    'nrt' => 'sla_missed_next_response',
    'rt' => 'sla_missed_resolution'
  }.freeze

  belongs_to :applied_sla
  belongs_to :conversation
  belongs_to :account
  belongs_to :sla_policy
  belongs_to :inbox

  enum :event_type, { frt: 0, nrt: 1, rt: 2 }

  before_validation :ensure_associated_ids
  after_create :notify_sla_miss

  def push_event_data
    {
      id: id,
      event_type: event_type,
      meta: meta,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def ensure_associated_ids
    self.account_id ||= conversation&.account_id
    self.inbox_id ||= conversation&.inbox_id
    self.sla_policy_id ||= applied_sla&.sla_policy_id
  end

  def notify_sla_miss
    notification_type = NOTIFICATION_TYPES[event_type]
    return if notification_type.blank?

    notifiable_users.each do |user|
      NotificationBuilder.new(
        notification_type: notification_type,
        user: user,
        account: account,
        primary_actor: conversation
      ).perform
    end
  end

  def notifiable_users
    users = [conversation.assignee]
    users += conversation.conversation_participants.map(&:user)
    users += account.administrators
    users.compact.uniq
  end
end
