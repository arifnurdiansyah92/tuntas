class Captain::Llm::ConversationFaqService
  include Integrations::LlmInstrumentation

  SuggestionChangedError = Class.new(StandardError)

  SIMILARITY_DISTANCE_THRESHOLD = 0.2

  def initialize(assistant, conversation)
    @assistant = assistant
    @conversation = conversation
  end

  def generate_suggestions
    return [] if conversation.first_reply_created_at.blank?

    candidates = generate_candidates
    candidates.filter_map { |candidate| process_candidate(candidate) }
  end

  private

  attr_reader :assistant, :conversation

  def transcript
    @transcript ||= conversation.messages.order(:created_at).filter_map do |message|
      next if message.private?

      if message.incoming?
        "User: #{message.content}"
      elsif human_agent_message?(message)
        "Support Agent: #{message.content}"
      end
    end.join("\n")
  end

  def human_agent_message?(message)
    return false unless message.outgoing?
    return true if message.sender_type == 'User'
    return true if message.sender.blank? && message.content_attributes[:external_echo].present?

    false
  end

  def generate_candidates
    model = Llm::FeatureRouter.resolve(feature: 'conversation_faq_generation', account: conversation.account).fetch(:model)
    chat = RubyLLM.chat(model: model)
                  .with_temperature(0.2)
                  .with_params(response_format: { type: 'json_object' })
                  .with_instructions(Captain::Llm::ConversationFaqPromptsService.generator(language_english_name))

    response = instrument_llm_call(
      account_id: conversation.account_id,
      model: model,
      feature: 'conversation_faq_generation',
      messages: [{ role: 'user', content: transcript }]
    ) do
      chat.ask(transcript)
    end
    parse_faqs(response&.content)
  rescue RubyLLM::Error => e
    Rails.logger.error "LLM API Error: #{e.message}"
    []
  end

  def parse_faqs(content)
    return [] if content.blank?

    JSON.parse(content).fetch('faqs', [])
  rescue JSON::ParserError => e
    Rails.logger.error "Error in parsing GPT processed response: #{e.message}"
    []
  end

  def process_candidate(candidate)
    question = candidate['question']
    answer = candidate['answer']
    embedding = Captain::Llm::EmbeddingService.new(account_id: conversation.account_id).get_embedding("#{question}\n#{answer}")

    if duplicate_of_approved_response?(question, answer, embedding)
      record_observation(question, answer, status: :discarded)
      return nil
    end

    attach_or_create_suggestion(question, answer, embedding)
  end

  def duplicate_of_approved_response?(question, answer, embedding)
    nearest = assistant.responses.approved.nearest_neighbors(:embedding, embedding, distance: 'cosine').first
    return false if nearest.blank? || nearest.neighbor_distance > SIMILARITY_DISTANCE_THRESHOLD

    same_faq?(question, answer, nearest.question, nearest.answer)
  end

  def attach_or_create_suggestion(question, answer, embedding)
    suggestion = nearest_open_suggestion(embedding)
    if suggestion && matches_suggestion?(suggestion, question, answer)
      attach_observation(suggestion, question, answer)
    else
      create_suggestion(question, answer, embedding)
    end
  end

  def nearest_open_suggestion(embedding)
    nearest = assistant.faq_suggestions.open.where(language: base_language)
                       .nearest_neighbors(:embedding, embedding, distance: 'cosine').first
    return if nearest.blank? || nearest.neighbor_distance > SIMILARITY_DISTANCE_THRESHOLD

    nearest
  end

  def matches_suggestion?(suggestion, question, answer)
    snapshot = [suggestion.question, suggestion.answer]
    matched = same_faq?(question, answer, suggestion.question, suggestion.answer)
    suggestion.reload
    raise SuggestionChangedError if snapshot != [suggestion.question, suggestion.answer]

    matched
  end

  def same_faq?(question, answer, existing_question, existing_answer)
    model = Llm::FeatureRouter.resolve(feature: 'conversation_faq_matching', account: conversation.account).fetch(:model)
    chat = RubyLLM.chat(model: model)
                  .with_temperature(0)
                  .with_params(response_format: { type: 'json_object' })
                  .with_instructions(Captain::Llm::ConversationFaqPromptsService.matcher)

    payload = {
      candidate: { question: question, answer: answer },
      existing: { question: existing_question, answer: existing_answer }
    }.to_json
    result = JSON.parse(chat.ask(payload).content).fetch('same_faq')
    raise TypeError, 'same_faq must be a boolean' unless [true, false].include?(result)

    result
  end

  def attach_observation(suggestion, question, answer)
    record_observation(question, answer, status: :attached, suggestion: suggestion)
    suggestion.increment!(:source_count) # rubocop:disable Rails/SkipsModelValidations
    suggestion
  end

  def create_suggestion(question, answer, embedding)
    suggestion = assistant.faq_suggestions.create!(
      question: question,
      answer: answer,
      embedding: embedding,
      language: base_language,
      source_count: 1
    )
    record_observation(question, answer, status: :attached, suggestion: suggestion)
    suggestion
  end

  def record_observation(question, answer, status:, suggestion: nil)
    Captain::FaqObservation.create!(
      account: conversation.account,
      conversation: conversation,
      faq_suggestion: suggestion,
      generated_question: question,
      generated_answer: answer,
      language: base_language,
      status: status
    )
  end

  def conversation_language
    conversation.additional_attributes&.dig('conversation_language').presence || conversation.account.locale
  end

  def base_language
    conversation_language.to_s.split(/[-_]/).first.presence || 'en'
  end

  def language_english_name
    ISO_639.find(base_language)&.english_name&.split(/[;,]/)&.first&.strip&.downcase || 'english'
  end
end
