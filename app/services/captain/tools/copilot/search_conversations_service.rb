class Captain::Tools::Copilot::SearchConversationsService < Captain::Tools::BaseService
  RESULT_LIMIT = 25

  def name
    'search_conversation'
  end

  def description
    'Search conversations based on parameters'
  end

  def parameters
    {
      status: {
        type: 'string',
        description: 'Filter conversations by status (open, resolved, pending, snoozed)'
      },
      contact_id: {
        type: 'number',
        description: 'Filter conversations by contact ID'
      },
      priority: {
        type: 'string',
        description: 'Filter conversations by priority (low, medium, high, urgent)'
      },
      labels: {
        type: 'array',
        description: 'Filter conversations carrying any of the given labels'
      }
    }
  end

  def execute(status: nil, contact_id: nil, priority: nil, labels: nil)
    conversations = filtered_conversations(status, contact_id, priority, labels).limit(RESULT_LIMIT)
    return 'No conversations found' if conversations.blank?

    sections = ["Total number of conversations: #{conversations.size}"]
    sections += conversations.map { |conversation| conversation.to_llm_text(include_contact_details: true) }
    sections.join("\n\n")
  end

  def active?
    user_has_permission?('conversation_manage', 'conversation_unassigned_manage', 'conversation_participating_manage')
  end

  private

  def filtered_conversations(status, contact_id, priority, labels)
    conversations = accessible_conversations
    conversations = conversations.where(status: status) if status.present? && Conversation.statuses.key?(status.to_s)
    conversations = conversations.where(contact_id: contact_id) if contact_id.present?
    conversations = conversations.where(priority: priority) if priority.present? && Conversation.priorities.key?(priority.to_s)
    conversations = conversations.tagged_with(labels, any: true) if labels.present?
    conversations
  end

  def accessible_conversations
    return account.conversations.none if user.blank?

    Conversations::PermissionFilterService.new(account.conversations, user, account).perform
  end
end
