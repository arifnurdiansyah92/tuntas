class Captain::Tools::UpdatePriorityTool < Captain::Tools::BasePublicTool
  VALID_PRIORITIES = %w[low medium high urgent].freeze
  REMOVE_PRIORITY_VALUES = ['nil', ''].freeze

  description 'Update the priority of a conversation'
  param :priority, type: 'string', desc: 'The priority level: low, medium, high, urgent, or nil to remove priority'

  def perform(tool_context, priority:)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' if conversation.blank?

    normalized_priority = priority.to_s.strip
    unless VALID_PRIORITIES.include?(normalized_priority) || REMOVE_PRIORITY_VALUES.include?(normalized_priority)
      return 'Invalid priority. Valid options: low, medium, high, urgent, nil'
    end

    new_priority = VALID_PRIORITIES.include?(normalized_priority) ? normalized_priority : nil
    conversation.update!(priority: new_priority)
    log_tool_usage('update_priority', { conversation_id: conversation.id, priority: new_priority })

    "Priority updated to '#{new_priority || 'none'}' for conversation ##{conversation.display_id}"
  end
end
