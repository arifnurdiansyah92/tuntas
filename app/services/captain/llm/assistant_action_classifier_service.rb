class Captain::Llm::AssistantActionClassifierService
  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
  end

  def classify(message_history:, assistant_response:)
    model = Llm::FeatureRouter.resolve(feature: 'assistant', account: @assistant.account).fetch(:model)
    chat = RubyLLM.chat(model: model)
                  .with_temperature(0)
                  .with_schema(Captain::AssistantActionSchema)
                  .with_instructions(Captain::Llm::SystemPromptsService.action_classifier(custom_instructions))

    response = chat.ask(classification_prompt(message_history, assistant_response))
    result = response.content
    result = {} unless result.is_a?(Hash)
    result.merge('model' => model)
  end

  private

  def custom_instructions
    @assistant.config['instructions']
  end

  def classification_prompt(message_history, assistant_response)
    transcript = message_history.map { |message| "#{message[:role] == 'user' ? 'User' : 'Assistant'}: #{message[:content]}" }.join("\n")
    sections = []
    sections << "<account_custom_instructions>\n#{custom_instructions}\n</account_custom_instructions>" if custom_instructions.present?
    sections << "<conversation_context>\n#{transcript}\n</conversation_context>"
    sections << "<assistant_response_to_classify>\n#{assistant_response}\n</assistant_response_to_classify>"
    sections.join("\n\n")
  end
end
