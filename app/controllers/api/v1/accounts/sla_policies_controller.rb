class Api::V1::Accounts::SlaPoliciesController < Api::V1::Accounts::BaseController
  before_action :fetch_sla_policy, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @sla_policies = Current.account.sla_policies
  end

  def show; end

  def create
    @sla_policy = Current.account.sla_policies.create!(sla_policy_params)
  end

  def update
    @sla_policy.update!(sla_policy_params)
  end

  def destroy
    DeleteObjectJob.perform_later(@sla_policy, Current.user, request.ip)
    head :ok
  end

  private

  def fetch_sla_policy
    @sla_policy = Current.account.sla_policies.find(params[:id])
  end

  def sla_policy_params
    params.require(:sla_policy).permit(
      :name,
      :description,
      :first_response_time_threshold,
      :next_response_time_threshold,
      :resolution_time_threshold,
      :only_during_business_hours
    )
  end
end
