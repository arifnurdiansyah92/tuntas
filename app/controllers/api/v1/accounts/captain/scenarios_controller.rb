class Api::V1::Accounts::Captain::ScenariosController < Api::V1::Accounts::Captain::BaseController
  before_action :set_assistant
  before_action :set_scenario, only: [:show, :update, :destroy]
  before_action :check_admin_authorization!, only: [:create, :update, :destroy]

  def index
    render json: { payload: @assistant.scenarios.enabled.order(:id).map { |scenario| scenario_json(scenario) } }
  end

  def show
    render json: scenario_json(@scenario)
  end

  def create
    scenario = @assistant.scenarios.create!(scenario_params.merge(account_id: Current.account.id))
    render json: scenario_json(scenario)
  end

  def update
    @scenario.update!(scenario_params)
    render json: scenario_json(@scenario)
  end

  def destroy
    @scenario.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = Current.account.captain_assistants.find(params[:assistant_id])
  end

  def set_scenario
    @scenario = @assistant.scenarios.find(params[:id])
  end

  def scenario_params
    params.require(:scenario).permit(:title, :description, :instruction, :enabled, tools: [])
  end

  def scenario_json(scenario)
    scenario.as_json(only: [:id, :title, :description, :instruction, :enabled, :tools, :assistant_id, :account_id])
  end
end
