class Captain::AssistantActionSchema < RubyLLM::Schema
  string :action, enum: %w[continue handoff resolve]
  string :action_reason
end
