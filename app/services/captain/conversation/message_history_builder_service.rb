class Captain::Conversation::MessageHistoryBuilderService
  RESOLUTION_MARKER = '[The conversation was marked resolved. Treat newer customer messages as a fresh enquiry.]'.freeze

  def initialize(conversation, include_resolution_markers: false)
    @conversation = conversation
    @include_resolution_markers = include_resolution_markers
  end

  def perform
    history_messages.filter_map { |message| history_entry(message) }
  end

  private

  def history_messages
    scope = @conversation.messages.where(private: false).order(:created_at, :id)
    types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    types << Message.message_types[:activity] if @include_resolution_markers
    scope.where(message_type: types)
  end

  def history_entry(message)
    return resolution_entry(message) if message.activity?

    if message.incoming?
      { content: Captain::OpenAiMessageBuilderService.new(message: message).generate_content, role: 'user' }
    else
      { content: assistant_content(message), role: 'assistant' }
    end
  end

  def resolution_entry(message)
    return unless resolution_activity?(message)

    { content: RESOLUTION_MARKER, role: 'assistant' }
  end

  def resolution_activity?(message)
    activity = message.content_attributes.with_indifferent_access[:activity]
    activity.present? && activity[:type] == 'conversation_status_changed' && activity[:status] == 'resolved'
  end

  def assistant_content(message)
    parts = response_parts(message)
    return message.content if parts.blank? || deleted?(message)

    Captain::Assistant::ResponseParts.new(Captain::Assistant::ResponseParts.sanitize(parts)).plain_text
  end

  def response_parts(message)
    parts = message.additional_attributes&.[](Captain::Assistant::ResponseParts::MESSAGE_ATTRIBUTE_KEY)
    parts.is_a?(Array) ? parts : nil
  end

  def deleted?(message)
    message.content_attributes.with_indifferent_access[:deleted].present?
  end
end
