class Sla::TriggerSlasForAccountsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.joins(:sla_policies).distinct.find_each do |account|
      next unless account.feature_enabled?('sla')

      Sla::ProcessAccountAppliedSlasJob.perform_later(account)
    end
  end
end
