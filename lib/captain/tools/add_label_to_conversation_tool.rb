class Captain::Tools::AddLabelToConversationTool < Captain::Tools::BasePublicTool
  description 'Add a label to a conversation'
  param :label_name, type: 'string', desc: 'The name of the label to add'

  def perform(tool_context, label_name:)
    normalized_label = label_name.to_s.strip.downcase
    return 'Label name is required' if normalized_label.blank?

    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' if conversation.blank?

    label = assistant.account.labels.find_by(title: normalized_label)
    return 'Label not found' if label.blank?

    conversation.add_labels([label.title])
    log_tool_usage('added_label', { conversation_id: conversation.id, label: label.title })

    "Label '#{label.title}' added to conversation ##{conversation.display_id}"
  end
end
