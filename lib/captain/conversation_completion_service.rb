class Captain::ConversationCompletionService
  FEATURE = 'conversation_completion'.freeze

  pattr_initialize [:account!, :conversation_display_id!]

  def perform
    return { complete: false, reason: 'No messages found' } if transcript_messages.blank?
    return { complete: false, reason: I18n.t('captain.disabled') } unless account.feature_enabled?('captain_tasks')
    return { complete: false, reason: I18n.t('captain.api_key_missing') } if system_api_key.blank?

    evaluate
  rescue StandardError => e
    { complete: false, reason: e.message }
  end

  private

  def conversation
    @conversation ||= account.conversations.find_by(display_id: conversation_display_id)
  end

  def transcript_messages
    @transcript_messages ||= conversation.messages
                                         .where(message_type: [:incoming, :outgoing])
                                         .where(private: false)
                                         .order(:created_at)
                                         .to_a
  end

  def evaluate
    result = nil
    Llm::Config.with_api_key(system_api_key, api_base: api_base) do |context|
      chat = context.chat(model: model)
      chat.with_instructions(system_prompt)
      chat = chat.with_schema(Captain::ConversationCompletionSchema)
      response = chat.ask(evaluation_context)
      result = parse_result(response.content)
    end
    result
  end

  def parse_result(content)
    return { complete: false, reason: 'Invalid response format' } unless content.is_a?(Hash)

    { complete: content['complete'] == true, reason: content['reason'] }
  end

  def model
    if TuntasApp.self_hosted_enterprise?
      account.captain_models&.dig(FEATURE).presence ||
        InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
        Llm::Models.default_model_for(FEATURE)
    else
      Llm::Models.default_model_for(FEATURE)
    end
  end

  def system_prompt
    <<~PROMPT
      You evaluate whether a customer support conversation is complete.
      A conversation is complete when the customer's request has been fully addressed and no follow-up from either side is pending.
      Answer with complete: false when a question is unanswered, a follow-up was promised, or the customer is still waiting.
    PROMPT
  end

  def evaluation_context
    transcript = transcript_messages.map { |message| "#{speaker_label(message)}: #{message.content_for_llm}" }.join("\n")
    <<~CONTEXT
      Conversation status: #{conversation.status}

      Conversation transcript:
      #{transcript}
    CONTEXT
  end

  def speaker_label(message)
    return 'Customer' if message.incoming?
    return 'Captain' if message.sender_type == 'Captain::Assistant'

    'Agent'
  end

  def system_api_key
    @system_api_key ||= InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end

  def api_base
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence
  end
end
