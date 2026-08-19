class Captain::Llm::AssistantFalsePromiseService
  DETECTOR_MODEL = 'gpt-5.2'.freeze

  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
  end

  def detect(message_history:, assistant_response:)
    chat = RubyLLM.chat(model: DETECTOR_MODEL)
                  .with_temperature(0)
                  .with_schema(Captain::AssistantFalsePromiseSchema)
                  .with_instructions(Captain::Llm::SystemPromptsService.false_promise_detector)

    response = chat.ask(detection_prompt(message_history, assistant_response))
    result = response.content
    result = {} unless result.is_a?(Hash)
    result.merge('model' => DETECTOR_MODEL)
  end

  private

  def detection_prompt(message_history, assistant_response)
    transcript = message_history.map { |message| "#{message[:role] == 'user' ? 'User' : 'Assistant'}: #{message[:content]}" }.join("\n")
    <<~PROMPT
      <conversation_context>
      #{transcript}
      </conversation_context>

      <assistant_response_to_check>
      #{assistant_response}
      </assistant_response_to_check>
    PROMPT
  end
end
