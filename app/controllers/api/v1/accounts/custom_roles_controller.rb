class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_custom_role, only: [:show, :update, :destroy]

  def index
    render json: Current.account.custom_roles
  end

  def show
    render json: @custom_role
  end

  def create
    render json: Current.account.custom_roles.create!(custom_role_params)
  end

  def update
    @custom_role.update!(custom_role_params)
    render json: @custom_role
  end

  def destroy
    @custom_role.destroy!
    head :ok
  end

  private

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.find(params[:id])
  end

  def custom_role_params
    params.require(:custom_role).permit(:name, :description, permissions: [])
  end
end
