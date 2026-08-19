class Api::V1::Accounts::Captain::CopilotThreadsController < Api::V1::Accounts::Captain::BaseController
  CREDIT_LIMIT_MESSAGE = 'You are out of Copilot credits. You can buy more credits from the billing section.'.freeze

  def index
    threads = threads_scope.order(created_at: :desc, id: :desc)
    render json: { payload: paginate(threads).map { |thread| thread_json(thread) } }
  end

  def create
    return render json: { error: 'Message is required' }, status: :unprocessable_entity if params[:message].blank?

    assistant = Current.account.captain_assistants.find(params[:assistant_id])
    thread = create_thread(assistant)

    if copilot_credits_exhausted?
      thread.copilot_messages.create!(account_id: Current.account.id, message_type: :assistant,
                                      message: { content: CREDIT_LIMIT_MESSAGE })
    else
      enqueue_response(thread, assistant)
    end

    render json: thread_json(thread)
  end

  private

  def threads_scope
    Current.account.copilot_threads.where(user_id: Current.user.id)
  end

  def create_thread(assistant)
    thread = Current.account.copilot_threads.create!(
      title: params[:message],
      user_id: Current.user.id,
      assistant: assistant
    )
    thread.copilot_messages.create!(account_id: Current.account.id, message_type: :user, message: { content: params[:message] })
    thread
  end

  def copilot_credits_exhausted?
    limit = Current.account.limits.to_h['captain_responses']
    return false if limit.blank?

    Current.account.custom_attributes['captain_responses_usage'].to_i >= limit.to_i
  end

  def enqueue_response(thread, assistant)
    Captain::Copilot::ResponseJob.perform_later(
      assistant: assistant,
      conversation_id: params[:conversation_id],
      user_id: Current.user.id,
      copilot_thread_id: thread.id,
      message: params[:message]
    )
  end

  def thread_json(thread)
    thread.as_json(only: [:id, :title, :account_id, :assistant_id, :created_at, :updated_at])
          .merge('user' => { 'id' => thread.user_id, 'name' => thread.user.name })
  end
end
