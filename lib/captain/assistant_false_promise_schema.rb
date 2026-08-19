class Captain::AssistantFalsePromiseSchema < RubyLLM::Schema
  string :decision, enum: %w[safe future_work_promise]
  string :reason
end
