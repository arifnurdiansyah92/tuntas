class Sla::EvaluateAppliedSlaService
  pattr_initialize [:applied_sla!]

  def perform
    return if conversation.contact&.blocked?

    if conversation.resolved?
      finalize_applied_sla
    else
      check_frt_miss
      check_nrt_miss
      check_rt_miss
      applied_sla.update!(sla_status: 'active_with_misses') if misses_exist? && !applied_sla.active_with_misses?
    end
  end

  private

  delegate :conversation, :sla_policy, to: :applied_sla

  def finalize_applied_sla
    if misses_exist?
      applied_sla.update!(sla_status: 'missed', completed_at: Time.zone.now)
    else
      applied_sla.update!(sla_status: 'hit', completed_at: Time.zone.now)
      Rails.logger.info("SLA hit for conversation #{conversation.id} in account " \
                        "#{applied_sla.account_id} for sla_policy #{applied_sla.sla_policy_id}")
    end
  end

  def check_frt_miss
    return if sla_policy.first_response_time_threshold.blank?
    return if conversation.first_reply_created_at.present?
    return unless overdue?(applied_sla.frt_due_at)

    record_miss('frt') unless miss_recorded?('frt')
  end

  def check_nrt_miss
    return if sla_policy.next_response_time_threshold.blank?
    return if conversation.first_reply_created_at.blank?
    return if conversation.waiting_since.blank?
    return unless overdue?(applied_sla.nrt_due_at)

    # A fresh nag is recorded on every evaluation while the customer keeps waiting;
    # it stops once the agent replies (waiting_since cleared) or the conversation resolves.
    record_miss('nrt')
  end

  def check_rt_miss
    return if sla_policy.resolution_time_threshold.blank?
    return unless overdue?(applied_sla.rt_due_at)

    record_miss('rt') unless miss_recorded?('rt')
  end

  def overdue?(due_at)
    due_at.present? && Time.zone.now.to_i > due_at
  end

  def record_miss(type)
    SlaEvent.create!(
      applied_sla: applied_sla,
      conversation: conversation,
      event_type: type,
      account_id: applied_sla.account_id,
      sla_policy_id: applied_sla.sla_policy_id,
      inbox_id: conversation.inbox_id
    )
    Rails.logger.warn("SLA #{type} missed for conversation #{conversation.id} in account " \
                      "#{applied_sla.account_id} for sla_policy #{applied_sla.sla_policy_id}")
  end

  def miss_recorded?(type)
    applied_sla.sla_events.exists?(event_type: type)
  end

  def misses_exist?
    applied_sla.sla_events.exists?
  end
end
