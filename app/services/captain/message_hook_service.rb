# Bridges incoming customer messages to the Captain assistant: records demand
# eligibility, enforces the response quota, and schedules the response builder.
# Invoked from MessageTemplates::HookExecutionService on every created message.
class Captain::MessageHookService
  BASE_WAIT_SECONDS = 1
  ATTACHMENT_BURST_WINDOW = 30.seconds

  pattr_initialize [:message!]

  delegate :conversation, :inbox, to: :message
  delegate :account, to: :conversation

  def perform
    return unless captain_applicable?

    record_eligibility if captain_v2?
    return unless conversation.pending?
    return handle_quota_exceeded if quota_exceeded?

    schedule_response_job
  end

  # Templates (greeting, out-of-office, email collect) stay silent while Captain
  # owns the conversation; once handed off (open) they behave as usual.
  def suppress_templates?
    assistant.present? && conversation.pending?
  end

  private

  def assistant
    return @assistant if defined?(@assistant)

    @assistant = inbox.captain_assistant
  end

  def captain_applicable?
    message.incoming? && assistant.present? && !bot_integration_inbox?
  end

  def bot_integration_inbox?
    inbox.agent_bot.present? || Integrations::Hook.exists?(inbox_id: inbox.id, status: :enabled)
  end

  def captain_v2?
    account.feature_enabled?('captain_integration_v2')
  end

  def record_eligibility
    Captain::ConversationOutcomeTracker
      .new(conversation: conversation, assistant: assistant)
      .record_eligibility(at: message.created_at)
  end

  def quota_exceeded?
    limit = account.limits.to_h['captain_responses']
    return false if limit.blank?

    account.custom_attributes['captain_responses_usage'].to_i >= limit.to_i
  end

  def handle_quota_exceeded
    conversation.bot_handoff!
    Captain::ConversationEvents.handed_off(
      conversation: conversation, assistant: assistant, source: 'usage_limit', reason_category: :usage_limit, at: Time.zone.now
    )
  end

  def schedule_response_job
    wait = attachment_wait_seconds
    job = wait.positive? ? Captain::Conversation::ResponseBuilderJob.set(wait: wait.seconds) : Captain::Conversation::ResponseBuilderJob

    if captain_v2?
      job.perform_later(conversation, assistant, message.id)
    else
      job.perform_later(conversation, assistant)
    end
  end

  # A message carrying attachments waits a moment so multi-file uploads land in
  # one response. Captain V2 stretches the wait across the whole recent burst.
  def attachment_wait_seconds
    attachment_count = captain_v2? ? burst_attachment_count : message.attachments.size
    return 0 if attachment_count.zero?

    BASE_WAIT_SECONDS + attachment_count
  end

  def burst_attachment_count
    recent_message_ids = conversation.messages.captain_response_triggering
                                     .where(created_at: ATTACHMENT_BURST_WINDOW.ago..)
                                     .select(:id)
    Attachment.where(message_id: recent_message_ids).count
  end
end
