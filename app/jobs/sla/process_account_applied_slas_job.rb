class Sla::ProcessAccountAppliedSlasJob < ApplicationJob
  queue_as :medium

  def perform(account)
    return unless account.feature_enabled?('sla')

    account.applied_slas
           .where(sla_status: [:active, :active_with_misses])
           .with_sla_applicable_conversation
           .find_each do |applied_sla|
      Sla::ProcessAppliedSlaJob.perform_later(applied_sla)
    end
  end
end
