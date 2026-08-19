class Captain::Tools::FirecrawlParserJob < ApplicationJob
  queue_as :low

  def perform(assistant_id:, payload:)
    assistant = Captain::Assistant.find(assistant_id)
    metadata = payload[:metadata] || {}
    external_link = canonical_link(metadata['sourceURL'].presence || metadata['url'])

    document = assistant.documents.find_or_initialize_by(external_link: external_link)
    document.assign_attributes(
      account: assistant.account,
      name: metadata['title'],
      content: payload[:markdown],
      status: :available,
      sync_status: :synced,
      last_synced_at: Time.current,
      last_sync_attempted_at: Time.current
    )
    document.save!
  rescue StandardError => e
    raise "Failed to parse FireCrawl data: #{e.message}"
  end

  private

  def canonical_link(url)
    url.to_s.chomp('/')
  end
end
