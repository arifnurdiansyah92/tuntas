class Captain::Tools::BasePublicTool < Agents::Tool
  STALE_TOOL_MESSAGE = 'Tool skipped because a newer customer message arrived'.freeze

  attr_reader :assistant

  def initialize(assistant)
    super()
    @assistant = assistant
  end

  def active?
    true
  end

  def execute(tool_context, **params)
    return STALE_TOOL_MESSAGE if stale_guard_enabled? && stale_context?(tool_context)

    perform(tool_context, **params)
  end

  protected

  def stale_guard_enabled?
    assistant.account.feature_enabled?('captain_integration_v2')
  end

  def stale_context?(tool_context)
    responding_to_message_id = tool_context.state[:responding_to_message_id]
    return false if responding_to_message_id.blank?

    conversation = find_conversation(tool_context.state)
    return false if conversation.blank?

    newer_customer_message_exists?(conversation, responding_to_message_id)
  end

  def newer_customer_message_exists?(conversation, responding_to_message_id)
    conversation.messages.incoming.exists?(['messages.id > ?', responding_to_message_id])
  end

  def find_conversation(state)
    conversation_id = state.dig(:conversation, :id)
    return if conversation_id.blank?

    Conversation.where(account_id: assistant.account_id).find_by(id: conversation_id)
  end

  def find_contact(state)
    contact_id = state.dig(:contact, :id)
    return if contact_id.blank?

    assistant.account.contacts.find_by(id: contact_id)
  end

  def log_tool_usage(event, payload = {})
    Rails.logger.info("[Captain] #{self.class.name} #{event} #{payload.inspect}")
  end
end
