class Captain::Tools::SimplePageCrawlParserJob < ApplicationJob
  PermanentCrawlError = Class.new(StandardError)

  queue_as :low
  discard_on PermanentCrawlError

  MAX_NAME_LENGTH = 255
  MAX_CONTENT_LENGTH = 15_000

  def perform(assistant_id:, page_link:)
    assistant = Captain::Assistant.find(assistant_id)
    canonical_link = page_link.chomp('/')
    crawler = Captain::Tools::SimplePageCrawlService.new(page_link)

    handle_fetch_failure(assistant, canonical_link, page_link, crawler) unless crawler.success?

    store_document(assistant, canonical_link, crawler)
  rescue PermanentCrawlError
    raise
  rescue StandardError => e
    raise "Failed to parse data: #{page_link} #{e.message}"
  end

  private

  def handle_fetch_failure(assistant, canonical_link, page_link, crawler)
    error_code = crawler.status_code == 404 ? 'not_found' : 'fetch_failed'
    mark_existing_document_failed(assistant, canonical_link, error_code)

    raise PermanentCrawlError, "Failed to parse data: #{page_link} Failed to fetch page: #{page_link}" if error_code == 'not_found'

    raise "Failed to fetch page: #{page_link}"
  end

  def mark_existing_document_failed(assistant, canonical_link, error_code)
    document = assistant.documents.find_by(external_link: canonical_link)
    return if document.blank?

    document.update!(
      status: :available,
      sync_status: :failed,
      last_sync_error_code: error_code,
      last_sync_attempted_at: Time.current
    )
  end

  def store_document(assistant, canonical_link, crawler)
    document = assistant.documents.find_or_initialize_by(external_link: canonical_link)
    document.assign_attributes(
      account: assistant.account,
      name: crawler.page_title.to_s.first(MAX_NAME_LENGTH),
      content: crawler.body_markdown.to_s.first(MAX_CONTENT_LENGTH),
      status: :available,
      sync_status: :synced,
      last_synced_at: Time.current,
      last_sync_attempted_at: Time.current
    )
    document.save!
  end
end
