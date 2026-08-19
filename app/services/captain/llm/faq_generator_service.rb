class Captain::Llm::FaqGeneratorService
  def initialize(document:)
    @document = document
  end

  def generate
    response = chat.ask(@document.content)
    parse_response(response&.content)
  rescue RubyLLM::Error => e
    Rails.logger.error "LLM API Error: #{e.message}"
    []
  end

  private

  def chat
    model = Llm::FeatureRouter.resolve(feature: 'document_faq_generation', account: @document.account).fetch(:model)
    RubyLLM.chat(model: model)
           .with_temperature(0.2)
           .with_params(response_format: { type: 'json_object' })
           .with_instructions(Captain::Llm::SystemPromptsService.faq_generator(@document.account.locale_english_name))
  end

  def parse_response(content)
    return [] if content.blank?

    JSON.parse(content).fetch('faqs')
  rescue JSON::ParserError => e
    Rails.logger.error "Error in parsing GPT processed response: #{e.message}"
    []
  rescue KeyError
    []
  end
end
