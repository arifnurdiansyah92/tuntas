class Api::V1::Accounts::Captain::AssistantStatsController < Api::V1::Accounts::Captain::BaseController
  before_action :set_assistant

  def overview
    render json: overview_builder.metrics
  end

  def overview_summary
    render json: Captain::AssistantStatsBuilder.new(@assistant, params[:range], params[:timezone_offset]).metrics
  end

  def resolution_flow
    render json: Captain::AssistantResolutionFlowBuilder.new(@assistant, params[:range], params[:timezone_offset]).build
  end

  def resolution_trend
    render json: Captain::AssistantResolutionTrendStatsBuilder.new(@assistant, params[:range], params[:timezone_offset]).metrics
  end

  private

  def set_assistant
    @assistant = Current.account.captain_assistants.find(params[:assistant_id])
  end

  def overview_builder
    Captain::AssistantOverviewStatsBuilder.new(@assistant, params[:range], params[:timezone_offset])
  end
end
