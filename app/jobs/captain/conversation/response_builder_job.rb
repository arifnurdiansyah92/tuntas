class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  queue_as :default

  MAX_MESSAGE_LENGTH = 10_000
  HANDOFF_TOKEN = 'conversation_handoff'.freeze

  def perform(conversation, assistant, responding_to_message_id = nil)
    @conversation = conversation
    @assistant = assistant
    @account = conversation.account
    @responding_to_message_id = responding_to_message_id
    return unless conversation.pending?

    Current.executed_by = assistant
    captain_v2? ? perform_v2 : perform_v1
  ensure
    Current.executed_by = nil
  end

  private

  def captain_v2?
    @account.feature_enabled?('captain_integration_v2')
  end

  # ==== V1: single-shot chat completion pipeline ====

  def perform_v1
    history = Captain::Conversation::MessageHistoryBuilderService.new(@conversation).perform
    response = v1_chat_service.generate_response(message_history: history)
    text = response['response'].to_s

    return v1_handoff('response') if handoff_token?(text)
    return unless @conversation.reload.pending?
    return v1_handoff('classifier') if classifier_requests_handoff?(history, text)

    text = review_false_promises(history, text)
    return if text.nil?

    create_assistant_message(text)
    @account.increment_response_usage
  rescue StandardError => e
    handle_v1_error(e)
  end

  def v1_chat_service
    @v1_chat_service ||= Captain::Llm::AssistantChatService.new(assistant: @assistant, conversation: @conversation)
  end

  def handoff_token?(text)
    text.include?(HANDOFF_TOKEN)
  end

  def classifier_requests_handoff?(history, text)
    return false unless @account.feature_enabled?('captain_v1_action_classifier')

    result = Captain::Llm::AssistantActionClassifierService
             .new(assistant: @assistant, conversation: @conversation)
             .classify(message_history: history, assistant_response: text)
    result.is_a?(Hash) && result['action'] == 'handoff'
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: @account).capture_exception
    false
  end

  # Returns the (possibly repaired) response text, or nil when the draft was
  # handed off instead.
  def review_false_promises(history, text)
    return text if @account.captain_false_promise_harness_enabled.blank?

    outcome = Captain::Conversation::V1FalsePromiseHandler.new(
      assistant: @assistant, conversation: @conversation, chat_service: v1_chat_service, message_history: history
    ).review(text)
    return outcome[:response] if outcome[:action] == Captain::Conversation::V1FalsePromiseHandler::SEND

    v1_handoff('false_promise')
    nil
  end

  def handle_v1_error(error)
    TuntasExceptionTracker.new(error, account: @account).capture_exception
    v1_handoff('error', reason: error_reason(error))
  end

  def error_reason(error)
    error.class.name.underscore.tr('/', '_')
  end

  # The handoff message must be created before bot_handoff!: its commit callback
  # clears waiting_since (bot_response), after which bot_handoff! stamps the
  # handoff time so a later human reply is tracked as a reply to the customer.
  def v1_handoff(source, reason: 'handoff')
    Rails.logger.info(
      "Captain response builder handoff account_id=#{@account.id} " \
      "conversation_id=#{@conversation.display_id} source=#{source} reason=#{reason}"
    )
    create_assistant_message(I18n.t('conversations.captain.handoff'))
    @conversation.bot_handoff!
    MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation) unless @conversation.campaign_id?
  end

  # ==== V2: agent runner pipeline ====

  def perform_v2
    runner = Captain::Assistant::AgentRunnerService.new(
      assistant: @assistant, conversation: @conversation, responding_to_message_id: @responding_to_message_id
    )
    history = Captain::Conversation::MessageHistoryBuilderService.new(@conversation, include_resolution_markers: true).perform
    response = generate_v2_response(runner, history)
    return if response.nil?

    return handle_v2_failure(runner, response['error_reason'].presence || 'standard_error') if response['error'].present?
    return handle_v2_handoff(runner) if response['handoff_tool_called']
    return unless fresh_response?(runner)

    deliver_v2_response(runner, response)
  end

  def generate_v2_response(runner, history)
    runner.generate_response(message_history: history)
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: @account).capture_exception
    handle_v2_failure(runner, error_reason(e))
    nil
  end

  def handle_v2_failure(runner, reason)
    Captain::ConversationEvents.response_failed(conversation: @conversation, assistant: @assistant, reason: reason, at: Time.zone.now)
    return unless fresh_response?(runner)

    Captain::ConversationEvents.handed_off(
      conversation: @conversation, assistant: @assistant, source: 'generation_failure', reason_category: :tool_failure, at: Time.zone.now
    )
    v1_handoff('generation_failure', reason: reason)
  end

  def handle_v2_handoff(runner)
    if runner.handoff_completed?
      create_assistant_message(I18n.t('conversations.captain.handoff'), preserve_waiting_since: true)
    else
      Captain::ConversationEvents.handed_off(
        conversation: @conversation, assistant: @assistant, source: 'tool', reason_category: :tool_failure, at: Time.zone.now
      )
      v1_handoff('tool', reason: 'handoff_uncommitted')
    end
    capture_session(runner, handoff_result_message(runner), 0.0)
  end

  def handoff_result_message(runner)
    note_id = run_state(runner).dig(:cw_metadata, :handoff_note_id)
    note = @conversation.messages.find_by(id: note_id) if note_id.present?
    note || @conversation.messages.outgoing.where(private: false).last
  end

  def deliver_v2_response(runner, response)
    parts = Captain::Assistant::ResponseParts.from_response(response)
    return if parts.blank?

    message = create_assistant_message(
      rendered_content(runner, parts),
      additional_attributes: { Captain::Assistant::ResponseParts::MESSAGE_ATTRIBUTE_KEY => parts.parts }
    )
    Captain::ConversationEvents.response_completed(conversation: @conversation, assistant: @assistant, message: message, at: Time.zone.now)
    capture_session(runner, message, 1.0)
    @account.increment_response_usage
  end

  def rendered_content(runner, parts)
    citation_urls = @assistant.customer_visible_citation_urls(citation_sources(runner))
    parts.customer_message_content(citation_urls: citation_urls)
  end

  def citation_sources(runner)
    sources = run_state(runner)[Captain::Assistant::CITATION_SOURCES_STATE_KEY]
    sources.is_a?(Hash) ? sources : {}
  end

  def run_state(runner)
    context = runner.last_run_result&.context
    state = context.respond_to?(:[]) ? context[:state] : nil
    state.is_a?(Hash) ? state : {}
  end

  def capture_session(runner, result_message, credits_consumed)
    Captain::Assistant::SessionCaptureService.new(
      assistant: @assistant,
      conversation: @conversation,
      run_result: runner.last_run_result,
      result_message: result_message,
      credits_consumed: credits_consumed
    ).capture
  end

  def fresh_response?(runner)
    return false if runner.response_discarded?
    return true if @responding_to_message_id.blank?

    !newer_customer_message_arrived?
  end

  def newer_customer_message_arrived?
    @conversation.messages
                 .where(message_type: :incoming)
                 .where(id: (@responding_to_message_id + 1)..)
                 .any? { |message| message.content_attributes.with_indifferent_access.dig('email', 'auto_reply').blank? }
  end

  def create_assistant_message(content, preserve_waiting_since: false, additional_attributes: nil)
    message = @conversation.messages.build(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :outgoing,
      content: content.to_s.first(MAX_MESSAGE_LENGTH),
      sender: @assistant
    )
    message.additional_attributes = additional_attributes if additional_attributes.present?
    message.preserve_waiting_since = preserve_waiting_since
    message.save!
    message
  end
end
