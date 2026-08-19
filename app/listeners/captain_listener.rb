class CaptainListener < BaseListener
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    assistant = conversation.inbox.captain_assistant
    return if assistant.blank?

    generate_contact_notes(assistant, conversation) if assistant.config['feature_memory'].present?
    Captain::Llm::ConversationFaqJob.perform_later(conversation, assistant) if assistant.config['feature_faq'].present?

    Captain::ConversationOutcomeTracker
      .new(conversation: conversation, assistant: assistant)
      .record_resolution(at: event.timestamp)
  end

  def message_updated(event)
    message = event.data[:message]
    return unless message.input_csat?

    response = CsatSurveyResponse.find_by(message_id: message.id)
    return if response.blank?

    Captain::ConversationOutcomeTracker
      .new(conversation: message.conversation, assistant: nil)
      .record_csat(response: response)
  end

  private

  def generate_contact_notes(assistant, conversation)
    Captain::Llm::ContactNotesService.new(assistant, conversation).generate_and_update_notes
  end
end
