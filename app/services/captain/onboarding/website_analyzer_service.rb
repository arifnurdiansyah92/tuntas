class Captain::Onboarding::WebsiteAnalyzerService
  ANALYSIS_TEMPERATURE = 0.1
  ANALYSIS_MODEL = 'gpt-4.1-mini'.freeze

  def initialize(website_url)
    @website_url = normalize_url(website_url)
  end

  def analyze
    content = fetch_website_content
    return failure('Failed to fetch website content') if content.blank?

    business_info = extract_business_info(content)
    return failure('Failed to parse business information from website') if business_info.blank?

    success(business_info)
  rescue StandardError => e
    failure(e.message)
  end

  private

  def normalize_url(url)
    normalized = url.to_s.strip
    normalized = "https://#{normalized}" unless normalized.match?(%r{\Ahttps?://})
    normalized
  end

  def crawler
    @crawler ||= Captain::Tools::SimplePageCrawlService.new(@website_url)
  end

  def fetch_website_content
    sections = [crawler.body_markdown, crawler.page_title, crawler.meta_description]
    sections.filter_map(&:presence).join("\n\n").first(15_000)
  rescue StandardError
    nil
  end

  def extract_business_info(content)
    chat = RubyLLM.chat(model: ANALYSIS_MODEL)
                  .with_temperature(ANALYSIS_TEMPERATURE)
                  .with_params(response_format: { type: 'json_object' })
                  .with_instructions(system_prompt)

    parse_business_info(chat.ask(content).content)
  end

  def system_prompt
    <<~PROMPT
      You analyze a company website to bootstrap an AI support assistant.
      From the provided page content, extract the business name, suggest a friendly assistant name,
      and write a short second-person description of what the assistant specializes in.

      Return strictly valid JSON:
      {"business_name": "...", "suggested_assistant_name": "...", "description": "..."}
    PROMPT
  end

  def parse_business_info(content)
    parsed = content.is_a?(Hash) ? content : JSON.parse(content)
    return if parsed['business_name'].blank? && parsed['suggested_assistant_name'].blank?

    parsed
  rescue JSON::ParserError
    nil
  end

  def success(business_info)
    {
      success: true,
      data: {
        business_name: business_info['business_name'],
        suggested_assistant_name: business_info['suggested_assistant_name'],
        description: business_info['description'],
        website_url: @website_url,
        favicon_url: favicon_url
      }
    }
  end

  def favicon_url
    crawler.favicon_url
  rescue StandardError
    nil
  end

  def failure(error)
    { success: false, error: error }
  end
end
