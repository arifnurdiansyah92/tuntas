class Captain::Assistant::AgentRunnerService
  MAX_TURNS = 10
  CONVERSATION_STATE_ATTRIBUTES = %i[id display_id inbox_id contact_id status priority].freeze
  CONTACT_STATE_ATTRIBUTES = %i[id name email phone_number identifier contact_type].freeze
  CAMPAIGN_STATE_ATTRIBUTES = %i[id title message campaign_type description].freeze

  attr_reader :last_run_result, :responding_to_message_id

  def initialize(assistant:, conversation: nil, callbacks: {}, responding_to_message_id: nil, source: nil)
    @assistant = assistant
    @conversation = conversation
    @callbacks = callbacks
    @responding_to_message_id = responding_to_message_id
    @source = source
  end

  def generate_response(message_history:)
    @runner = build_runner
    input_entry = last_user_entry(message_history)
    context = build_context(message_history - [input_entry].compact)
    add_trace_payloads(context, message_history, input_entry)

    result = @runner.run(runner_input(input_entry), context: context, max_turns: MAX_TURNS)
    @last_run_result = result
    process_result(result)
  rescue StandardError => e
    handle_error(e)
  end

  def handoff_completed?
    @handoff_completed == true
  end

  def response_discarded?
    return true if @response_discarded
    return false if @responding_to_message_id.blank? || @conversation.blank?

    newer_customer_message_arrived?
  end

  private

  def build_runner
    agents = build_agents
    runner = Agents::Runner.with_agents(*agents)
    add_usage_metadata_callback(runner)
    runner
  end

  def build_agents
    primary = @assistant.agent
    scenario_agents = @assistant.scenarios.enabled.map(&:agent)
    if scenario_agents.any?
      primary.register_handoffs(*scenario_agents)
      scenario_agents.each { |scenario_agent| scenario_agent.register_handoffs(primary) }
    end

    [primary, *scenario_agents]
  end

  def add_usage_metadata_callback(runner)
    runner.on_tool_complete do |tool_name, tool_result, context_wrapper|
      track_handoff_usage(tool_name, tool_result, context_wrapper)
    end
    return runner unless TuntasApp.otel_enabled? || @responding_to_message_id.present?

    runner.on_run_complete do |_agent_name, _result, context_wrapper|
      finalize_run_metadata(context_wrapper)
    end
    runner
  end

  def track_handoff_usage(tool_name, _tool_result, context_wrapper)
    return unless tool_name.to_s == handoff_tool_name

    context = context_wrapper.context
    context[:captain_v2_handoff_tool_called] = true
    @handoff_tool_called = true
    @handoff_completed = true if context.dig(:state, :captain_v2_handoff_tool_completed).present?
  end

  def finalize_run_metadata(context_wrapper)
    discarded = @responding_to_message_id.present? && newer_customer_message_arrived?
    @response_discarded = true if discarded

    context = context_wrapper.context
    root_span = context.dig(:__otel_tracing, :root_span)
    return if root_span.blank?

    handoff = context[:captain_v2_handoff_tool_called].present? || @handoff_tool_called.present?
    root_span.set_attribute('langfuse.trace.metadata.discarded', 'true') if discarded
    root_span.set_attribute('langfuse.trace.metadata.credit_used', (!handoff && !discarded).to_s)
  end

  def handoff_tool_name
    @handoff_tool_name ||= Captain::Tools::HandoffTool.new(@assistant).name
  end

  def newer_customer_message_arrived?
    @conversation.messages
                 .where(message_type: :incoming)
                 .where(id: (@responding_to_message_id + 1)..)
                 .any? { |message| !auto_reply?(message) }
  end

  def auto_reply?(message)
    message.content_attributes.with_indifferent_access.dig('email', 'auto_reply').present?
  end

  def build_context(message_history)
    {
      session_id: session_id,
      conversation_history: message_history.map { |entry| serialize_history_entry(entry) },
      state: build_state
    }
  end

  def add_trace_payloads(context, full_history, input_entry)
    context[:captain_v2_trace_input] = JSON.generate(full_history)
    context[:captain_v2_trace_current_input] = JSON.generate(input_entry ? entry_content(input_entry) : nil)
  end

  def serialize_history_entry(entry)
    {
      role: entry_value(entry, :role).to_s.to_sym,
      content: entry_content(entry),
      agent_name: entry_value(entry, :agent_name)
    }
  end

  def session_id
    return @assistant.account_id.to_s if @conversation.blank?

    "#{@assistant.account_id}_#{@conversation.display_id}"
  end

  def build_state
    state = {
      account_id: @assistant.account_id,
      assistant_id: @assistant.id,
      assistant_config: @assistant.config
    }
    state[:responding_to_message_id] = @responding_to_message_id if @responding_to_message_id.present?
    state.merge!(conversation_state)
    state
  end

  def conversation_state
    return {} if @conversation.blank?

    state = {
      conversation: CONVERSATION_STATE_ATTRIBUTES.index_with { |attribute| @conversation.public_send(attribute) },
      channel_type: @conversation.inbox.channel_type
    }
    contact_inbox = @conversation.contact_inbox
    state[:contact_inbox] = { id: contact_inbox.id, hmac_verified: contact_inbox.hmac_verified } if contact_inbox.present?
    contact = @conversation.contact
    state[:contact] = CONTACT_STATE_ATTRIBUTES.index_with { |attribute| contact.public_send(attribute) } if contact.present?
    campaign = @conversation.campaign
    state[:campaign] = CAMPAIGN_STATE_ATTRIBUTES.index_with { |attribute| campaign.public_send(attribute) } if campaign.present?
    state
  end

  def last_user_entry(message_history)
    message_history.reverse.find { |entry| entry_value(entry, :role).to_s == 'user' }
  end

  def runner_input(input_entry)
    return '' if input_entry.blank?

    extract_last_user_message([input_entry])
  end

  def extract_last_user_message(message_history)
    entry = last_user_entry(message_history)
    return '' if entry.blank?

    content = entry_content(entry)
    content.is_a?(Array) ? multimodal_content(content) : content
  end

  def multimodal_content(content_parts)
    text = content_parts.filter_map { |part| entry_value(part, :text) if entry_value(part, :type) == 'text' }.join(' ')
    images = content_parts.filter_map do |part|
      next unless entry_value(part, :type) == 'image_url'

      image = entry_value(part, :image_url)
      image && (image[:url] || image['url'])
    end

    RubyLLM::Content.new(text, images)
  end

  def extract_text_from_content(content)
    case content
    when Array
      content.filter_map { |part| entry_value(part, :text) if entry_value(part, :type) == 'text' }.join(' ')
    when Hash
      response_parts = content['response_parts']
      return Captain::Assistant::ResponseParts.new(Captain::Assistant::ResponseParts.sanitize(response_parts)).plain_text if response_parts

      content['response'].to_s
    else
      content.to_s
    end
  end

  def process_result(result)
    output = result.output
    parts = Captain::Assistant::ResponseParts.from_response(output)
    parts = parts.without_citations unless citations_enabled?
    parts = enforce_channel_limit(parts, result)

    {
      'response_parts' => parts.parts,
      'response' => parts.plain_text,
      'reasoning' => output.is_a?(Hash) ? output['reasoning'] : 'Processed by agent',
      'agent_name' => context_value(result, :current_agent),
      'handoff_tool_called' => handoff_tool_called?(result)
    }
  end

  def handoff_tool_called?(result)
    @handoff_tool_called == true || context_value(result, :captain_v2_handoff_tool_called) == true
  end

  def context_value(result, key)
    context = result.context
    return nil unless context.respond_to?(:[])

    context[key]
  end

  def citations_enabled?
    @assistant.config['feature_citation'].present?
  end

  def enforce_channel_limit(parts, result)
    limit = Captain::MessageLengthLimit.for(@conversation)
    return parts if limit.blank? || parts.blank?

    citation_urls = @assistant.customer_visible_citation_urls(citation_sources(result))
    rendered = parts.customer_message_content(citation_urls: citation_urls)
    return parts if rendered.length <= limit

    rewrite_response_parts(parts, result, limit, rendered.length - parts.plain_text.length)
  end

  def citation_sources(result)
    sources = context_value(result, :state)&.[](Captain::Assistant::CITATION_SOURCES_STATE_KEY)
    sources.is_a?(Hash) ? sources : {}
  end

  def rewrite_response_parts(parts, result, limit, citation_markup_length)
    rewrite_result = @runner.run(rewrite_prompt(parts, limit - citation_markup_length), context: result.context, max_turns: 1)
    rewritten = Captain::Assistant::ResponseParts.from_response(rewrite_result.output)
    validate_rewrite!(parts, rewritten)

    final = Captain::Assistant::ResponseParts.new(
      rewritten.parts.each_with_index.map do |part, index|
        part.merge('citation_indexes' => parts.parts[index]['citation_indexes'])
      end
    )
    result.output['response_parts'] = final.parts if result.output.is_a?(Hash)
    final
  end

  def rewrite_prompt(parts, response_text_limit)
    <<~PROMPT
      Your previous reply is too long for this messaging channel. Rewrite it shorter: the combined response text must be at most #{response_text_limit} characters.
      Keep the same number and order of response parts, keep each part's "citation_indexes" exactly as given, and preserve the key information.
      Original response parts:
      #{JSON.generate(parts.parts)}
    PROMPT
  end

  def validate_rewrite!(original, rewritten)
    matching = original.parts.length == rewritten.parts.length &&
               original.parts.zip(rewritten.parts).all? { |before, after| before['citation_indexes'] == after['citation_indexes'] }
    raise StandardError, 'Captain response rewrite changed the response part citation order' unless matching
  end

  def handle_error(error)
    Rails.logger.error("[Captain V2] AgentRunnerService error: #{error.message}")
    Rails.logger.error(error.backtrace&.join("\n").to_s)
    TuntasExceptionTracker.new(error, account: @conversation&.account).capture_exception

    {
      'response' => 'conversation_handoff',
      'response_parts' => [{ 'text' => 'conversation_handoff', 'citation_indexes' => [] }],
      'reasoning' => "Error occurred: #{error.message}",
      'error' => true,
      'error_reason' => error.class.name.underscore.tr('/', '_'),
      'handoff_tool_called' => @handoff_tool_called == true
    }
  end

  def dynamic_trace_attributes(context_wrapper)
    context = context_wrapper.context || {}
    state = context[:state] || {}

    attributes = {
      'langfuse.user.id' => state[:account_id].to_s,
      'langfuse.trace.metadata.assistant_id' => state[:assistant_id].to_s
    }
    conversation_state = state[:conversation] || {}
    attributes['langfuse.trace.metadata.conversation_id'] = conversation_state[:id].to_s if conversation_state[:id].present?
    add_trace_input_attributes(attributes, context)
    attributes
  end

  def add_trace_input_attributes(attributes, context)
    trace_input = context[:captain_v2_trace_input]
    return if trace_input.blank?

    attributes['langfuse.trace.input'] = trace_input
    attributes['langfuse.observation.input'] = context[:captain_v2_trace_current_input].presence || trace_input
  end

  def entry_value(entry, key)
    entry[key] || entry[key.to_s]
  end

  def entry_content(entry)
    entry_value(entry, :content)
  end
end
