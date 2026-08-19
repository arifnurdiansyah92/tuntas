class Captain::Assistant::SessionCaptureService
  def initialize(assistant:, conversation:, run_result:, result_message:, credits_consumed:)
    @assistant = assistant
    @conversation = conversation
    @run_result = run_result
    @result_message = result_message
    @credits_consumed = credits_consumed
  end

  def capture
    capture!
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: @assistant.account).capture_exception
    nil
  end

  def capture!
    return if @run_result.blank? || @run_result.error.present?

    Captain::AgentSession.create!(
      assistant: @assistant,
      session_type: :assistant,
      subject: @conversation,
      result: @result_message,
      llm_model: llm_model,
      credits_consumed: @credits_consumed,
      faq_ids: metadata_ids(:faq_ids),
      used_faq_ids: metadata_ids(:used_faq_ids),
      cited_document_ids: cited_document_ids,
      document_ids: metadata_ids(:document_ids),
      scenario_ids: scenario_ids,
      run_context: serialized_current_turn
    )
  end

  private

  def context
    value = @run_result.context
    value.is_a?(Hash) ? value : {}
  end

  def state
    value = context[:state]
    value.is_a?(Hash) ? value : {}
  end

  def metadata_ids(key)
    metadata = state[:cw_metadata]
    return [] unless metadata.is_a?(Hash)

    Array(metadata[key])
  end

  def llm_model
    model = @assistant.send(:agent_model)
    provider = Llm::Models.provider_for(model) || 'openai'
    "#{provider}-#{model}"
  end

  def cited_document_ids
    sources = state[Captain::Assistant::CITATION_SOURCES_STATE_KEY]
    return [] unless sources.is_a?(Hash) && sources.present?

    visible_urls = @assistant.customer_visible_citation_urls(sources)
    cited_indexes.select { |index| visible_urls.key?(index) }.map { |index| sources[index] }.uniq
  end

  def cited_indexes
    output = @run_result.output
    return [] unless output.is_a?(Hash)

    Captain::Assistant::ResponseParts.sanitize(Array(output['response_parts'])).flat_map { |part| part['citation_indexes'] }.uniq
  end

  def scenario_ids
    names = current_turn_history.filter_map do |entry|
      entry[:agent_name] if entry[:role].to_s == 'assistant' && entry[:agent_name].present?
    end.uniq

    scenarios = @assistant.scenarios.to_a
    names.filter_map { |name| scenarios.find { |scenario| scenario.handoff_key == name }&.id }
  end

  def current_turn_history
    @current_turn_history ||= begin
      history = Array(context[:conversation_history])
      last_user_index = history.rindex { |entry| entry[:role].to_s == 'user' }
      last_user_index ? history[last_user_index..] : history
    end
  end

  def serialized_current_turn
    current_turn_history.map { |entry| serialize_entry(entry) }
  end

  def serialize_entry(entry)
    entry.each_with_object({}) do |(key, value), memo|
      memo[key.to_s] = key.to_s == 'content' ? serialize_content(value) : serialize_value(value)
    end
  end

  def serialize_value(value)
    value.is_a?(Symbol) ? value.to_s : value
  end

  def serialize_content(content)
    return content unless content.is_a?(RubyLLM::Content)

    {
      'text' => content.text,
      'attachments' => content.attachments.map do |attachment|
        { 'type' => attachment_type(attachment), 'source' => attachment.source.to_s }
      end
    }
  end

  def attachment_type(attachment)
    return attachment.type.to_s if attachment.respond_to?(:type)

    %w[image audio pdf].find { |kind| attachment.respond_to?("#{kind}?") && attachment.public_send("#{kind}?") } || 'file'
  end
end
