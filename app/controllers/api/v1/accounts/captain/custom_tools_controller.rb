class Api::V1::Accounts::Captain::CustomToolsController < Api::V1::Accounts::Captain::BaseController
  before_action :set_custom_tool, only: [:show, :update, :destroy]
  before_action :check_admin_authorization!, only: [:create, :update, :destroy, :test]

  def index
    render json: { payload: custom_tools_scope.order(:id).map { |custom_tool| custom_tool_json(custom_tool) } }
  end

  def show
    render json: custom_tool_json(@custom_tool)
  end

  def create
    custom_tool = custom_tools_scope.create!(custom_tool_params)
    render json: custom_tool_json(custom_tool)
  end

  def update
    @custom_tool.update!(custom_tool_params)
    render json: custom_tool_json(@custom_tool)
  end

  def destroy
    @custom_tool.destroy!
    head :no_content
  end

  def test
    custom_tool = custom_tools_scope.find(params[:id]) if params[:id].present?
    custom_tool ||= custom_tools_scope.new(custom_tool_params)
    result = custom_tool.tool(nil).execute(**test_params)
    render json: { result: result }
  end

  private

  def set_custom_tool
    @custom_tool = custom_tools_scope.find(params[:id])
  end

  def custom_tools_scope
    Current.account.captain_custom_tools
  end

  def custom_tool_params
    params.require(:custom_tool).permit(
      :title, :description, :endpoint_url, :http_method, :enabled, :request_template, :response_template, :auth_type,
      param_schema: [:name, :type, :description, :required], auth_config: {}
    )
  end

  def test_params
    params.fetch(:params, {}).permit!.to_h.symbolize_keys
  end

  def custom_tool_json(custom_tool)
    custom_tool.as_json(
      only: [:id, :title, :description, :slug, :endpoint_url, :http_method, :enabled, :param_schema, :account_id, :created_at, :updated_at]
    )
  end
end
