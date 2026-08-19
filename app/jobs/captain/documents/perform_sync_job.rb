class Captain::Documents::PerformSyncJob < ApplicationJob
  queue_as :purgable

  LOCK_TIMEOUT = 30.minutes

  def perform(document)
    @document = document

    with_lock do
      document.update!(sync_status: :syncing, last_sync_attempted_at: Time.current)
      result = Captain::Documents::SinglePageFetcher.new(document).fetch
      apply_result(document, result)
    end
  rescue StandardError => e
    mark_failed(document, 'sync_error')
    raise e
  end

  private

  def with_lock(&)
    @document.with_lock(&)
  end

  def apply_result(document, result)
    if result.success
      document.update!(
        sync_status: :synced,
        last_synced_at: Time.current,
        last_sync_attempted_at: Time.current,
        last_sync_error_code: nil,
        name: result.title.presence || document.name,
        content: result.content
      )
    else
      document.update!(
        sync_status: :failed,
        last_sync_error_code: result.error_code,
        last_sync_attempted_at: Time.current
      )
    end
  end

  def mark_failed(document, error_code)
    document.update_columns( # rubocop:disable Rails/SkipsModelValidations
      sync_status: Captain::Document.sync_statuses[:failed],
      last_sync_error_code: error_code,
      last_sync_attempted_at: Time.current
    )
  end
end
