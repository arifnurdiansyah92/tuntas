class Captain::Tools::ResolveConversationTool < Captain::Tools::BasePublicTool
  description 'Resolve the conversation when the customer issue is fully addressed'
  param :reason, type: 'string', desc: 'Why the conversation can be resolved', required: false

  def perform(tool_context, reason: nil)
    return 'Auto-resolve is disabled for this assistant' if assistant.auto_resolve_mode == 'disabled'

    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' if conversation.blank?
    return "Conversation ##{conversation.display_id} is already resolved" if conversation.resolved?

    conversation.resolved!
    enqueue_activity_message(conversation, reason)
    Captain::ConversationEvents.resolved(conversation: conversation, assistant: assistant, source: 'tool', at: Time.zone.now)
    log_tool_usage('resolve_conversation', { conversation_id: conversation.id, reason: reason })

    "Conversation ##{conversation.display_id} resolved"
  end

  private

  def enqueue_activity_message(conversation, reason)
    content = I18n.t('conversations.activity.captain.resolved_by_tool', user_name: assistant.name, reason: reason)
    Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    )
  end
end
