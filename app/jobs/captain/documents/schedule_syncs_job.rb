class Captain::Documents::ScheduleSyncsJob < ApplicationJob
  queue_as :scheduled_jobs

  WEEKLY_SYNC_JITTER = 4.hours
  SYNC_STALE_TIMEOUT = 2.hours

  def perform(plan_name = nil)
    @global_remaining = config_limit('CAPTAIN_DOCUMENT_AUTO_SYNC_GLOBAL_BATCH_LIMIT', 1000)

    Account.joins(:captain_assistants).distinct.find_each do |account|
      break if @global_remaining <= 0
      next unless account.feature_enabled?('captain_document_auto_sync')
      next if plan_name.present? && account_plan(account) != plan_name.to_s.downcase

      interval_hours = sync_intervals[account_plan(account)]
      next if interval_hours.blank?

      schedule_account_syncs(account, interval_hours.to_i.hours)
    end
  end

  private

  def account_plan(account)
    account.custom_attributes['plan_name'].to_s.downcase
  end

  def sync_intervals
    @sync_intervals ||= JSON.parse(InstallationConfig.find_by(name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS')&.value.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def config_limit(name, default)
    InstallationConfig.find_by(name: name)&.value.presence&.to_i || default
  end

  def schedule_account_syncs(account, interval)
    limit = [config_limit('CAPTAIN_DOCUMENT_AUTO_SYNC_PER_ACCOUNT_BATCH_LIMIT', 50), @global_remaining].min
    due_documents(account, interval).limit(limit).each do |document|
      Captain::Documents::PerformSyncJob.set(wait: rand(0..WEEKLY_SYNC_JITTER.to_i)).perform_later(document)
      @global_remaining -= 1
    end
  end

  def due_documents(account, interval)
    due_before = (interval.to_i / 2).seconds.ago
    Captain::Document
      .where(account_id: account.id, status: :available)
      .where.not("external_link LIKE 'PDF: %' OR external_link ILIKE '%.pdf'")
      .where(due_condition, due_before: due_before, stale_before: SYNC_STALE_TIMEOUT.ago)
      .order(Arel.sql('last_sync_attempted_at ASC NULLS FIRST'))
  end

  def due_condition
    <<~SQL.squish
      (sync_status = #{Captain::Document.sync_statuses[:synced]} AND last_synced_at <= :due_before) OR
      (sync_status = #{Captain::Document.sync_statuses[:failed]} AND last_sync_attempted_at <= :due_before) OR
      (sync_status = #{Captain::Document.sync_statuses[:syncing]} AND last_sync_attempted_at <= :stale_before)
    SQL
  end
end
