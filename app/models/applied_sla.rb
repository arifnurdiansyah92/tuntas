# == Schema Information
#
# Table name: applied_slas
#
#  id              :bigint           not null, primary key
#  completed_at    :datetime
#  sla_status      :integer          default("active")
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  sla_policy_id   :bigint           not null
#
# Indexes
#
#  index_applied_slas_on_account_id                     (account_id)
#  index_applied_slas_on_account_sla_policy_conversation  (account_id,sla_policy_id,conversation_id) UNIQUE
#  index_applied_slas_on_conversation_id                (conversation_id)
#  index_applied_slas_on_sla_policy_id                  (sla_policy_id)
#
class AppliedSla < ApplicationRecord
  belongs_to :account
  belongs_to :sla_policy
  belongs_to :conversation
  has_many :sla_events, dependent: :destroy_async

  enum :sla_status, { active: 0, hit: 1, missed: 2, active_with_misses: 3 }

  scope :with_sla_applicable_conversation, lambda {
    left_outer_joins(conversation: :contact).where(contacts: { blocked: [false, nil] })
  }

  def push_event_data
    {
      id: id,
      sla_id: sla_policy_id,
      sla_status: sla_status,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i,
      sla_completed_at: completed_at&.to_i,
      sla_description: sla_policy.description,
      sla_name: sla_policy.name,
      sla_first_response_time_threshold: sla_policy.first_response_time_threshold,
      sla_next_response_time_threshold: sla_policy.next_response_time_threshold,
      sla_only_during_business_hours: sla_policy.only_during_business_hours,
      sla_resolution_time_threshold: sla_policy.resolution_time_threshold,
      sla_frt_due_at: frt_due_at,
      sla_nrt_due_at: nrt_due_at,
      sla_rt_due_at: rt_due_at
    }
  end

  def frt_due_at
    return if sla_policy.first_response_time_threshold.blank?

    calculate_due_at(conversation.created_at, sla_policy.first_response_time_threshold).to_i
  end

  def nrt_due_at
    return if sla_policy.next_response_time_threshold.blank?
    return if conversation.waiting_since.blank?

    calculate_due_at(conversation.waiting_since, sla_policy.next_response_time_threshold).to_i
  end

  def rt_due_at
    return if sla_policy.resolution_time_threshold.blank?

    calculate_due_at(conversation.created_at, sla_policy.resolution_time_threshold).to_i
  end

  private

  def calculate_due_at(start_time, threshold_seconds)
    return start_time + threshold_seconds unless sla_policy.only_during_business_hours

    Sla::BusinessHoursService.new(
      inbox: conversation.inbox,
      start_time: start_time,
      threshold_seconds: threshold_seconds,
      working_hours_by_day: working_hours_by_day
    ).deadline
  end

  def working_hours_by_day
    @working_hours_by_day ||= conversation.inbox.working_hours.index_by(&:day_of_week)
  end
end
