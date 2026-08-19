class Api::V1::Accounts::Captain::MessageReportsController < Api::V1::Accounts::Captain::BaseController
  before_action :ensure_cloud_installation!

  def create
    message = Current.account.messages.find(params[:message_id])
    authorize_conversation_access!(message.conversation)
    return render json: { error: 'Only Captain responses can be reported' }, status: :unprocessable_entity unless captain_message?(message)

    report = Captain::MessageReport.create!(
      account_id: Current.account.id,
      message: message,
      conversation: message.conversation,
      user: Current.user,
      report_reason: params[:report_reason],
      description: params[:description]
    )
    render json: report_json(report)
  end

  private

  def ensure_cloud_installation!
    raise ActiveRecord::RecordNotFound unless GlobalConfig.get_value('DEPLOYMENT_ENV') == 'cloud'
  end

  def authorize_conversation_access!(conversation)
    accessible = Conversations::PermissionFilterService.new(
      Current.account.conversations.where(id: conversation.id), Current.user, Current.account
    ).perform.exists?
    raise Pundit::NotAuthorizedError unless accessible
  end

  def captain_message?(message)
    message.sender_type == 'Captain::Assistant'
  end

  def report_json(report)
    report.as_json(only: [:id, :report_reason, :description, :message_id, :conversation_id, :user_id, :account_id, :created_at])
  end
end
