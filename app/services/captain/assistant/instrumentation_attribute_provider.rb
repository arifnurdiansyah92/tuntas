class Captain::Assistant::InstrumentationAttributeProvider
  def initialize(runner_service)
    @runner_service = runner_service
  end

  def call(context_wrapper)
    @runner_service.send(:dynamic_trace_attributes, context_wrapper)
  end

  def generation_attributes(_chat, _params, message)
    attributes = {
      'langfuse.observation.metadata.generation_stage' => message.tool_calls.present? ? 'tool_call' : 'final_response'
    }
    if @runner_service.responding_to_message_id.present?
      attributes['langfuse.observation.metadata.discarded'] = @runner_service.response_discarded?.to_s
    end
    attributes
  end
end
