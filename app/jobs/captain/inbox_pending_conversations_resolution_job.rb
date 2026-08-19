class Captain::InboxPendingConversationsResolutionJob < ApplicationJob
  queue_as :low

  def perform(inbox)
    @inbox = inbox
    @captain_assistant = CaptainInbox.find_by(inbox_id: inbox.id)&.captain_assistant
    return if @captain_assistant.blank?

    mode = @captain_assistant.auto_resolve_mode
    return if mode == 'disabled'

    @inactivity_cutoff_time = @captain_assistant.inactivity_threshold_minutes.to_i.minutes.ago

    resolvable_conversations(inbox).each do |conversation|
      process_conversation(conversation, inbox, mode)
    end
  end

  private

  def account
    @inbox.account
  end

  def resolvable_conversations(inbox)
    inbox.conversations.pending.where(last_activity_at: ...@inactivity_cutoff_time).limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def process_conversation(conversation, inbox, mode)
    if mode == 'evaluated' && account.feature_enabled?('captain_tasks')
      evaluated_action(conversation, inbox)
    else
      time_based_resolve(conversation)
    end
  end

  def time_based_resolve(conversation)
    send_resolution_message(conversation) if @captain_assistant.send_inactivity_resolution_message?
    conversation.resolved!
    Captain::ConversationEvents.resolved(
      conversation: conversation, assistant: @captain_assistant, source: 'time_based', at: Time.zone.now
    )
  end

  def evaluated_action(conversation, inbox)
    result = Captain::ConversationCompletionService.new(
      account: account, conversation_display_id: conversation.display_id
    ).perform
    # Skip the auto-action when the conversation saw new activity while the LLM evaluated it.
    return if conversation.reload.last_activity_at > @inactivity_cutoff_time

    if result[:complete]
      resolve_conversation(conversation, inbox, result[:reason])
    else
      handoff_conversation(conversation, result[:reason])
    end
  end

  def resolve_conversation(conversation, _inbox, reason)
    conversation.with_lock do
      create_private_note(conversation, "Auto-resolved: #{reason}")
      send_resolution_message(conversation)
      conversation.resolved!
    end
    Captain::ConversationEvents.resolved(
      conversation: conversation, assistant: @captain_assistant, source: 'inference', at: Time.zone.now
    )
    enqueue_activity_message(
      conversation, 'resolved',
      I18n.t('conversations.activity.captain.resolved_with_reason',
             user_name: @captain_assistant.name, reason: 'no outstanding questions')
    )
  end

  def handoff_conversation(conversation, reason)
    conversation.with_lock do
      create_private_note(conversation, "Auto-handoff: #{reason}")
      send_handoff_message(conversation)
      conversation.bot_handoff!(dispatch_event: false)
    end
    conversation.dispatch_bot_handoff_event
    Captain::ConversationEvents.handed_off(
      conversation: conversation, assistant: @captain_assistant, source: 'inference',
      reason_category: :pending_clarification, at: Time.zone.now
    )
    enqueue_activity_message(
      conversation, 'open',
      I18n.t('conversations.activity.captain.open_with_reason',
             user_name: @captain_assistant.name, reason: 'pending clarification from customer')
    )
    MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation) unless conversation.campaign_id?
  end

  def send_resolution_message(conversation)
    content = @captain_assistant.config['resolution_message'].presence || I18n.t('conversations.activity.auto_resolution_message')
    create_public_message(conversation, content)
  end

  def send_handoff_message(conversation)
    content = @captain_assistant.config['handoff_message'].presence
    return if content.blank?

    create_public_message(conversation, content, preserve_waiting_since: true)
  end

  def create_private_note(conversation, content)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      content: content,
      sender: @captain_assistant
    )
  end

  def create_public_message(conversation, content, preserve_waiting_since: false)
    message = conversation.messages.build(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: false,
      content: content,
      sender: @captain_assistant
    )
    message.preserve_waiting_since = preserve_waiting_since
    message.save!
    message
  end

  def enqueue_activity_message(conversation, status, content)
    Conversations::ActivityMessageJob.perform_later(
      conversation,
      {
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        message_type: :activity,
        content: content,
        content_attributes: { activity: { type: 'conversation_status_changed', status: status } }
      }
    )
  end
end
