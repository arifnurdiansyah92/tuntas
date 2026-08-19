class Captain::Copilot::ResponseJob < ApplicationJob
  queue_as :default

  def perform(assistant:, conversation_id:, user_id:, copilot_thread_id:, message:)
    # When a copilot thread exists the user message is already persisted in the
    # thread history, so no input is passed to avoid duplicating it.
    input = copilot_thread_id.present? ? nil : message&.[]('content')

    Captain::Copilot::ChatService.new(
      assistant,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      conversation_id: conversation_id
    ).generate_response(input)
  end
end
