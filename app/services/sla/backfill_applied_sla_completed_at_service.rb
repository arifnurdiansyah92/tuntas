class Sla::BackfillAppliedSlaCompletedAtService
  BATCH_SIZE = 500

  def initialize(account_id: nil, all_accounts: false, apply: false, after_id: nil, output: $stdout)
    @account_id = account_id
    @all_accounts = all_accounts
    @apply = apply
    @after_id = after_id
    @output = output
  end

  def perform
    validate_scope!

    stats = { dry_run: !@apply, eligible: 0, matched: 0, updated: 0, skipped: 0, processed: 0, last_id: @after_id }

    eligible_scope.find_each(batch_size: BATCH_SIZE) do |applied_sla|
      stats[:eligible] += 1
      stats[:processed] += 1
      stats[:last_id] = applied_sla.id

      resolution_end_time = latest_resolution_end_time(applied_sla)
      if resolution_end_time.blank?
        stats[:skipped] += 1
        next
      end

      stats[:matched] += 1
      next unless @apply

      # update_columns keeps updated_at untouched: this is a data backfill, not a record change
      applied_sla.update_columns(completed_at: resolution_end_time) # rubocop:disable Rails/SkipsModelValidations
      stats[:updated] += 1
    end

    @output.puts(stats.inspect)
    stats
  end

  private

  def validate_scope!
    return if @account_id.present? ^ @all_accounts

    raise ArgumentError, 'Provide exactly one of ACCOUNT_ID or ALL_ACCOUNTS=true'
  end

  def eligible_scope
    scope = @all_accounts ? AppliedSla.all : AppliedSla.where(account_id: @account_id)
    scope = scope.where(completed_at: nil, sla_status: [:hit, :missed]).order(:id)
    scope = scope.where('applied_slas.id > ?', @after_id) if @after_id.present?
    scope
  end

  def latest_resolution_end_time(applied_sla)
    ReportingEvent.where(
      account_id: applied_sla.account_id,
      conversation_id: applied_sla.conversation_id,
      name: 'conversation_resolved'
    ).where('event_end_time >= ?', applied_sla.created_at).maximum(:event_end_time)
  end
end
