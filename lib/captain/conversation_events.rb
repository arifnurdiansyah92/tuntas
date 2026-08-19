module Captain::ConversationEvents
  module_function

  def handed_off(conversation:, assistant:, source:, reason_category: nil, at: Time.zone.now)
    tracker(conversation, assistant).record_handoff(at: at, reason_category: reason_category)
    dispatch(
      Events::Types::CAPTAIN_CONVERSATION_HANDED_OFF, at, conversation,
      conversation: conversation, assistant: assistant, source: source, reason_category: reason_category
    )
  end

  def resolved(conversation:, assistant:, source:, at: Time.zone.now)
    tracker(conversation, assistant).record_resolution(at: at)
    dispatch(
      Events::Types::CAPTAIN_CONVERSATION_RESOLVED, at, conversation,
      conversation: conversation, assistant: assistant, source: source
    )
  end

  def response_completed(conversation:, assistant:, message:, at: Time.zone.now)
    dispatch(
      Events::Types::CAPTAIN_RESPONSE_COMPLETED, at, conversation,
      conversation: conversation, assistant: assistant, message: message
    )
  end

  def response_failed(conversation:, assistant:, reason:, at: Time.zone.now)
    dispatch(
      Events::Types::CAPTAIN_RESPONSE_FAILED, at, conversation,
      conversation: conversation, assistant: assistant, reason: reason
    )
  end

  def tracker(conversation, assistant)
    Captain::ConversationOutcomeTracker.new(conversation: conversation, assistant: assistant)
  end

  def dispatch(event_name, timestamp, conversation, payload)
    Rails.configuration.dispatcher.dispatch(event_name, timestamp, payload)
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: conversation.account).capture_exception
    nil
  end
end
