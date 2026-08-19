class Captain::Llm::ConversationFaqJob < MutexApplicationJob
  queue_as :low

  LOCK_TIMEOUT = 15.minutes.to_i

  retry_on_lock_conflict wait: 2.minutes, attempts: 3

  def perform(conversation, assistant)
    key = lock_key(conversation, assistant)
    with_lock(key, LOCK_TIMEOUT) do
      Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_suggestions
    end
  end

  private

  def lock_key(conversation, assistant)
    "CAPTAIN_CONVERSATION_FAQ_LOCK::#{assistant.id}::#{normalized_language(conversation)}"
  end

  def normalized_language(conversation)
    language = conversation.additional_attributes&.[]('conversation_language').presence || 'en'
    language.to_s.split(/[-_]/).first.downcase
  end
end
