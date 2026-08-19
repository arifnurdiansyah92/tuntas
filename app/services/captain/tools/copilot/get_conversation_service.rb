class Captain::Tools::Copilot::GetConversationService < Captain::Tools::BaseService
  def name
    'get_conversation'
  end

  def description
    'Get details of a conversation including messages and contact information'
  end

  def parameters
    {
      conversation_id: {
        type: 'number',
        description: 'The display ID of the conversation to fetch'
      }
    }
  end

  def execute(conversation_id: nil)
    conversation = account.conversations.find_by(display_id: conversation_id) if conversation_id.present?
    return 'Conversation not found' if conversation.blank? || !accessible?(conversation)

    conversation.to_llm_text(include_private_messages: true)
  end

  def active?
    user_has_permission?('conversation_manage', 'conversation_unassigned_manage', 'conversation_participating_manage')
  end

  private

  def accessible?(conversation)
    return false if user.blank?

    Conversations::PermissionFilterService.new(
      account.conversations.where(id: conversation.id), user, account
    ).perform.exists?
  end
end
