module Captain::ConversationEvents
  module_function

  def handed_off(conversation:, assistant:, source:, reason_category: nil, at: Time.zone.now) # rubocop:disable Lint/UnusedMethodArgument
    outcome = ConversationOutcome.where(conversation_id: conversation.id, assistant_id: assistant.id)
                                 .order(started_at: :desc).first
    return if outcome.blank?

    outcome.update(handoff_at: at, handoff_reason_category: reason_category)
  end

  def resolved(conversation:, assistant:, source:, at: Time.zone.now) # rubocop:disable Lint/UnusedMethodArgument
    outcome = ConversationOutcome.where(conversation_id: conversation.id, assistant_id: assistant.id)
                                 .order(started_at: :desc).first
    return if outcome.blank?

    outcome.update(resolved_at: at)
  end
end
