class Captain::Llm::AssistantChatService
  include Integrations::LlmInstrumentation

  DEFAULT_TEMPERATURE = 0.5

  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
  end

  def generate_response(message_history:, additional_message: nil)
    model = Llm::FeatureRouter.resolve(feature: 'assistant', account: @assistant.account).fetch(:model)

    instrument_agent_session(session_instrumentation_params(model)) do
      chat = build_chat(model)
      history = additional_message.present? ? message_history + [{ role: 'user', content: additional_message }] : message_history
      replay_history(chat, history[0...-1])
      response = ask_current_message(chat, history.last)
      parse_response(response)
    end
  end

  private

  def session_instrumentation_params(model)
    {
      account_id: @assistant.account_id,
      assistant_id: @assistant.id,
      model: model,
      metadata: {
        conversation_id: @conversation.id,
        channel_type: @conversation.inbox.channel_type
      }
    }
  end

  def build_chat(model)
    chat = RubyLLM.chat(model: model)
                  .with_temperature(temperature)
                  .with_params(response_format: { type: 'json_object' })
                  .with_instructions(system_prompt)
    chat = chat.on_end_message { |message| record_generation(chat, message) }
    @assistant.send(:agent_tools).reduce(chat) { |current_chat, tool| current_chat.with_tool(tool) }
  end

  def record_generation(chat, message)
    generation_attributes(chat, message)
  end

  def generation_attributes(_chat, message)
    stage = message.tool_calls.present? ? 'tool_call' : 'final_response'
    {
      'langfuse.observation.metadata.generation_stage' => stage,
      'gen_ai.usage.input_tokens' => message.input_tokens,
      'gen_ai.usage.output_tokens' => message.output_tokens
    }
  end

  def temperature
    (@assistant.config['temperature'].presence || DEFAULT_TEMPERATURE).to_f
  end

  def system_prompt
    prompt = Captain::Llm::SystemPromptsService.assistant_response_generator(
      @assistant.name,
      @assistant.config['instructions']
    )
    prompt += contact_information_section if @assistant.config['feature_contact_attributes']
    prompt
  end

  def contact_information_section
    contact = @conversation.contact
    return '' if contact.blank?

    attributes = ["name: #{contact.name}", "email: #{contact.email}"]
    contact.custom_attributes.to_h.each { |key, value| attributes << "#{key}: #{value}" }

    "\n[Contact Information]\n#{attributes.join("\n")}\n"
  end

  def replay_history(chat, history)
    history.each do |message|
      role = message[:role].to_sym
      text, images = extract_content(message)
      if images.any?
        chat.add_message(role: role, content: RubyLLM::Content.new(text, images))
      else
        chat.add_message(role: role, content: text)
      end
    end
  end

  def ask_current_message(chat, message)
    text, images = extract_content(message)
    if images.any?
      chat.ask(text, with: images)
    else
      chat.ask(text)
    end
  end

  def extract_content(message)
    content = message[:content]
    return [content, []] unless content.is_a?(Array)

    text = content.find { |part| part[:type] == 'text' }&.dig(:text)
    images = content.select { |part| part[:type] == 'image_url' }.map { |part| part.dig(:image_url, :url) }
    [text, images]
  end

  def parse_response(response)
    content = response.content
    return content if content.is_a?(Hash)

    JSON.parse(content)
  rescue JSON::ParserError
    { 'response' => content }
  end
end
