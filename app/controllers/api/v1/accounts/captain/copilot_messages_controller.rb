class Api::V1::Accounts::Captain::CopilotMessagesController < Api::V1::Accounts::Captain::BaseController
  before_action :set_copilot_thread

  def index
    messages = @copilot_thread.copilot_messages.order(:created_at, :id)
    render json: { payload: messages.map { |message| message_json(message) } }
  end

  def create
    message = @copilot_thread.copilot_messages.create!(
      account_id: Current.account.id,
      message_type: :user,
      message: { content: message_content }
    )
    render json: message_json(message)
  end

  private

  def set_copilot_thread
    @copilot_thread = Current.account.copilot_threads.where(user_id: Current.user.id).find(params[:copilot_thread_id])
  end

  def message_content
    raw = params[:message]
    raw.respond_to?(:permit!) ? raw.permit!.to_h : raw
  end

  def message_json(message)
    message.as_json(only: [:id, :message, :message_type, :copilot_thread_id, :account_id, :created_at])
  end
end
