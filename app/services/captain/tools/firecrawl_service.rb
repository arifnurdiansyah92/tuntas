class Captain::Tools::FirecrawlService
  CRAWL_ENDPOINT = 'https://api.firecrawl.dev/v2/crawl'.freeze
  DEFAULT_CRAWL_LIMIT = 10
  FIRECRAWL_EXCLUDE_TAGS = %w[nav footer aside script style img iframe form button input select textarea header].freeze

  def initialize
    @api_key = InstallationConfig.find_by!(name: 'CAPTAIN_FIRECRAWL_API_KEY').value
    raise 'Missing API key' if @api_key.blank?
  end

  def perform(url, webhook_url, crawl_limit = DEFAULT_CRAWL_LIMIT)
    HTTParty.post(
      CRAWL_ENDPOINT,
      headers: {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json'
      },
      body: {
        url: url,
        maxDiscoveryDepth: 50,
        sitemap: 'include',
        limit: crawl_limit,
        webhook: { url: webhook_url },
        scrapeOptions: {
          onlyMainContent: true,
          formats: ['markdown'],
          excludeTags: FIRECRAWL_EXCLUDE_TAGS,
          maxAge: 0
        }
      }.to_json
    )
  rescue StandardError => e
    raise "Failed to crawl URL: #{e.message}"
  end
end
