class Captain::Tools::HandoffTool < Captain::Tools::BasePublicTool
  REASON_CATEGORIES = %w[customer_request unsupported_request missing_information policy_restriction other].freeze
  STALE_HANDOFF_MESSAGE = 'Handoff skipped because a newer customer message arrived'.freeze

  description 'Hand off the conversation to a human agent when unable to assist further'
  param :reason, type: 'string', desc: 'Why the conversation needs a human agent', required: false
  param :reason_category, type: 'string', desc: 'The category of the handoff reason'

  # Handoff manages its own stale-message guard inside a row lock
  def execute(tool_context, **params)
    perform(tool_context, **params)
  end

  def params_schema
    {
      'type' => 'object',
      'properties' => {
        'reason' => { 'type' => 'string' },
        'reason_category' => { 'type' => 'string', 'enum' => REASON_CATEGORIES }
      },
      'required' => ['reason_category']
    }
  end

  def perform(tool_context, reason: nil, reason_category: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' if conversation.blank?

    handoff(tool_context, conversation, reason, reason_category)
  rescue StandardError => e
    Rails.logger.error("Captain handoff failed: #{e.class} #{e.message}")
    TuntasExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  def handoff(tool_context, conversation, reason, reason_category)
    state = tool_context.state
    if locked_handoff?(state)
      result = locked_handoff(state, conversation, reason)
      return result if result
    else
      create_handoff_note(state, conversation, reason)
      conversation.bot_handoff!
    end

    finalize_handoff(conversation, reason, reason_category)
    handoff_result_message(reason)
  end

  def locked_handoff?(state)
    state[:responding_to_message_id].present? && stale_guard_enabled?
  end

  # Returns a skip message when stale, nil when the handoff went through.
  def locked_handoff(state, conversation, reason)
    skipped = nil
    conversation.with_lock do
      if newer_customer_message_exists?(conversation, state[:responding_to_message_id])
        skipped = STALE_HANDOFF_MESSAGE
      else
        create_handoff_note(state, conversation, reason)
        conversation.bot_handoff!(dispatch_event: false)
      end
    end
    return skipped if skipped

    conversation.dispatch_bot_handoff_event
    state[:captain_v2_handoff_tool_completed] = true
    nil
  end

  def create_handoff_note(state, conversation, reason)
    note = conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      private: true,
      content: reason,
      sender: assistant
    )
    (state[:cw_metadata] ||= {})[:handoff_note_id] = note.id if reason.present?
    note
  end

  def finalize_handoff(conversation, reason, reason_category)
    send_out_of_office_message(conversation)
    Captain::ConversationEvents.handed_off(
      conversation: conversation,
      assistant: assistant,
      source: 'tool',
      reason_category: normalized_reason_category(reason_category),
      at: Time.zone.now
    )
    log_tool_usage('tool_handoff', { conversation_id: conversation.id, reason: reason || 'Agent requested handoff' })
  end

  def normalized_reason_category(reason_category)
    ConversationOutcome::HANDOFF_REASON_CATEGORIES.include?(reason_category) ? reason_category : nil
  end

  def handoff_result_message(reason)
    return "Conversation handed off to human support team (Reason: #{reason})" if reason.present?

    'Conversation handed off to human support team'
  end

  def send_out_of_office_message(conversation)
    inbox = conversation.inbox
    return unless inbox.working_hours_enabled? && inbox.out_of_office? && inbox.out_of_office_message.present?

    conversation.messages.create!(
      account: conversation.account,
      inbox: inbox,
      message_type: :template,
      content: inbox.out_of_office_message
    )
  end
end
