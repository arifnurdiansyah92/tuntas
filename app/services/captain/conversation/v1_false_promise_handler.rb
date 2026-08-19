class Captain::Conversation::V1FalsePromiseHandler
  FUTURE_PROMISE_REPAIR_INSTRUCTION = <<~INSTRUCTION.freeze
    Your previous draft promised future work you cannot perform (checking, investigating, monitoring, or following up later).
    Rewrite your answer without promising any future action. Either resolve the question with the knowledge you have,
    or ask the customer for the specific information you need to proceed.
  INSTRUCTION

  SEND = 'send'.freeze
  HANDOFF = 'handoff'.freeze

  def initialize(assistant:, conversation:, chat_service:, message_history:)
    @assistant = assistant
    @conversation = conversation
    @chat_service = chat_service
    @message_history = message_history
  end

  # Reviews a drafted V1 response. Returns { action: SEND, response: text } when a
  # safe response can go out, or { action: HANDOFF } when the draft (and its repair)
  # cannot be verified safe.
  def review(response_text)
    detection = detect(response_text)
    return send_action(response_text) unless detection['decision'] == 'future_work_promise'

    repair(response_text)
  end

  private

  def repair(response_text)
    repaired = generate_repair(response_text)
    return handoff_action if repaired.blank?

    verification = detect(repaired)
    return send_action(repaired) if verification['decision'] == 'safe'

    handoff_action
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: @conversation.account).capture_exception
    handoff_action
  end

  def generate_repair(response_text)
    repair_history = @message_history + [{ role: 'assistant', content: response_text }]
    result = @chat_service.generate_response(
      message_history: repair_history,
      additional_message: FUTURE_PROMISE_REPAIR_INSTRUCTION
    )
    result['response']
  end

  def detect(response_text)
    result = Captain::Llm::AssistantFalsePromiseService
             .new(assistant: @assistant, conversation: @conversation)
             .detect(message_history: @message_history, assistant_response: response_text)
    result.is_a?(Hash) ? result : {}
  end

  def send_action(response_text)
    { action: SEND, response: response_text }
  end

  def handoff_action
    { action: HANDOFF }
  end
end
