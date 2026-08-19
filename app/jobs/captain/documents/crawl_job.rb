class Captain::Documents::CrawlJob < ApplicationJob
  queue_as :low

  MAX_CRAWL_LIMIT = 500
  DEFAULT_CRAWL_LIMIT = 10

  def perform(document)
    return process_pdf(document) if document.pdf_document?

    firecrawl_api_key = InstallationConfig.find_by(name: 'CAPTAIN_FIRECRAWL_API_KEY')&.value
    if firecrawl_api_key.present?
      crawl_with_firecrawl(document, firecrawl_api_key)
    else
      crawl_with_simple_crawler(document)
    end
  end

  private

  def process_pdf(document)
    Captain::Llm::PdfProcessingService.new(document).process
    document.update!(status: :available)
  end

  def crawl_with_firecrawl(document, api_key)
    token = Digest::SHA256.hexdigest("#{api_key.to_s.last(4)}#{document.assistant_id}#{document.account_id}")
    webhook_url = Rails.application.routes.url_helpers.enterprise_webhooks_firecrawl_url
    Captain::Tools::FirecrawlService.new.perform(
      document.external_link,
      "#{webhook_url}?assistant_id=#{document.assistant_id}&token=#{token}",
      crawl_limit(document.account)
    )
  end

  def crawl_limit(account)
    available = account.usage_limits.dig(:captain, :documents, :current_available)
    return DEFAULT_CRAWL_LIMIT if available.blank?

    [available, MAX_CRAWL_LIMIT].min
  end

  def crawl_with_simple_crawler(document)
    crawler = Captain::Tools::SimplePageCrawlService.new(document.external_link)
    (crawler.page_links + [document.external_link]).uniq.each do |page_link|
      Captain::Tools::SimplePageCrawlParserJob.perform_later(assistant_id: document.assistant_id, page_link: page_link)
    end
  end
end
