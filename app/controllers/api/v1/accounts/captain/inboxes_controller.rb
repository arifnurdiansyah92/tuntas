class Api::V1::Accounts::Captain::InboxesController < Api::V1::Accounts::Captain::BaseController
  before_action :set_assistant
  before_action :check_admin_authorization!, only: [:create, :destroy]

  def index
    render json: { payload: @assistant.inboxes.map { |inbox| inbox_json(inbox) } }
  end

  def create
    inbox = Current.account.inboxes.find(params.require(:inbox)[:inbox_id])
    @assistant.captain_inboxes.create!(inbox: inbox)
    render json: inbox_json(inbox)
  end

  def destroy
    captain_inbox = @assistant.captain_inboxes.find_by!(inbox_id: params[:inbox_id])
    captain_inbox.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = Current.account.captain_assistants.find(params[:assistant_id])
  end

  def inbox_json(inbox)
    inbox.as_json(only: [:id, :name, :channel_type, :account_id])
  end
end
