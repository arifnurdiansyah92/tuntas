class Sla::ProcessAppliedSlaJob < ApplicationJob
  queue_as :medium

  def perform(applied_sla)
    return unless applied_sla.account.feature_enabled?('sla')

    Sla::EvaluateAppliedSlaService.new(applied_sla: applied_sla).perform
  end
end
