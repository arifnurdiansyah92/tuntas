class Captain::ConversationCompletionSchema < RubyLLM::Schema
  boolean :complete
  string :reason
end
