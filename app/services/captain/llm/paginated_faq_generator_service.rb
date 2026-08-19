class Captain::Llm::PaginatedFaqGeneratorService
  MAX_ITERATIONS = 20

  attr_reader :iterations_completed

  def initialize(document, options = {})
    @document = document
    @pages_per_chunk = options[:pages_per_chunk] || 5
    @iterations_completed = 0
  end

  def total_pages_processed
    @iterations_completed * @pages_per_chunk
  end

  def model
    Llm::FeatureRouter.resolve(feature: 'pdf_faq_generation', account: @document.account).fetch(:model)
  end

  def generate
    raise CustomExceptions::Pdf::FaqGenerationError.new(document_id: @document.id) if @document.openai_file_id.blank?

    faqs = []
    loop do
      chunk = generate_chunk((@iterations_completed * @pages_per_chunk) + 1)
      @iterations_completed += 1
      faqs.concat(chunk[:faqs])
      break unless should_continue_processing?(faqs: chunk[:faqs], has_content: chunk[:has_content])
    end
    faqs
  end

  def should_continue_processing?(faqs:, has_content:)
    return false if @iterations_completed >= MAX_ITERATIONS
    return false if faqs.blank?

    has_content
  end

  private

  def generate_chunk(start_page)
    response = openai_client.chat(
      parameters: {
        model: model,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: Captain::Llm::SystemPromptsService.faq_generator(@document.account.locale_english_name) },
          {
            role: 'user',
            content: [
              { type: 'file', file: { file_id: @document.openai_file_id } },
              { type: 'text',
                text: "Extract FAQs from pages #{start_page} to #{start_page + @pages_per_chunk - 1}. " \
                      'Include "has_content": false when those pages have no content.' }
            ]
          }
        ]
      }
    )
    parse_chunk(response)
  end

  def parse_chunk(response)
    content = response.dig('choices', 0, 'message', 'content')
    parsed = JSON.parse(content)
    { faqs: parsed['faqs'] || [], has_content: parsed['has_content'] ? true : false }
  rescue JSON::ParserError, TypeError
    { faqs: [], has_content: false }
  end

  def openai_client
    @openai_client ||= OpenAI::Client.new(access_token: InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value)
  end
end
