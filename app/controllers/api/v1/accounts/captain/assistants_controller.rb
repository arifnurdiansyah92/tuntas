class Api::V1::Accounts::Captain::AssistantsController < Api::V1::Accounts::Captain::BaseController
  ALLOWED_CONFIG_KEYS = %w[
    product_name instructions temperature response_window audience
    feature_faq feature_memory feature_citation feature_contact_attributes
    auto_resolve_mode auto_resolve_after send_inactivity_resolution_message
    resolution_message handoff_message
  ].freeze
  V2_ONLY_CONFIG_KEYS = %w[auto_resolve_after send_inactivity_resolution_message resolution_message handoff_message].freeze

  before_action :set_assistant, except: [:index, :create, :tools]
  before_action -> { authorize(@assistant || Captain::Assistant) }

  def index
    assistants = assistants_scope.order(id: :desc)
    render json: {
      payload: paginate(assistants).map { |assistant| assistant_json(assistant) },
      meta: pagination_meta(assistants.count)
    }
  end

  def show
    render json: assistant_json(@assistant)
  end

  def create
    assistant = assistants_scope.new(assistant_attributes)
    assistant.config = default_config.merge(sanitized_config || {})
    assistant.save!
    render json: assistant_json(assistant)
  end

  def update
    assign_assistant_attributes
    @assistant.config = @assistant.config.merge(sanitized_config) if sanitized_config.present?
    @assistant.save!
    render json: assistant_json(@assistant)
  end

  def destroy
    @assistant.destroy!
    head :no_content
  end

  def tools
    render json: { payload: Captain::Scenario.built_in_agent_tools }
  end

  def metrics
    render json: Captain::AssistantStatsBuilder.new(@assistant, params[:range], params[:timezone_offset]).metrics
  end

  def faq_stats
    render json: faq_stats_payload
  end

  def summary
    cached = Rails.cache.read(summary_cache_key)
    return render json: cached if cached.present?

    result = generate_summary
    return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error].present?

    Rails.cache.write(summary_cache_key, result, expires_in: 1.hour)
    render json: result
  end

  def drilldown
    sessions = Captain::AgentSession.where(assistant_id: @assistant.id).order(created_at: :desc)
    render json: {
      payload: paginate(sessions).map { |session| { id: session.id, subject_id: session.subject_id, created_at: session.created_at.to_i } },
      meta: pagination_meta(sessions.count)
    }
  end

  def playground
    render json: playground_response
  end

  private

  def set_assistant
    @assistant = assistants_scope.find(params[:id])
  end

  def assistants_scope
    Current.account.captain_assistants
  end

  def assistant_attributes
    params.require(:assistant).permit(:name, :description, response_guidelines: [], guardrails: [])
  end

  def assign_assistant_attributes
    assistant_params = params.require(:assistant)
    @assistant.name = assistant_params[:name] if assistant_params.key?(:name)
    @assistant.description = assistant_params[:description] if assistant_params.key?(:description)
    @assistant.response_guidelines = assistant_params[:response_guidelines] if assistant_params.key?(:response_guidelines)
    @assistant.guardrails = assistant_params[:guardrails] if assistant_params.key?(:guardrails)
  end

  def sanitized_config
    raw = params.dig(:assistant, :config)
    return nil if raw.blank?

    config = raw.permit!.to_h.deep_stringify_keys.slice(*ALLOWED_CONFIG_KEYS)
    config = config.except(*V2_ONLY_CONFIG_KEYS) unless Current.account.feature_enabled?('captain_integration_v2')
    config
  end

  def default_config
    { 'auto_resolve_mode' => Current.account.captain_auto_resolve_mode }
  end

  def assistant_json(assistant)
    assistant.as_json(
      only: [:id, :name, :description, :response_guidelines, :guardrails, :config, :account_id, :created_at, :updated_at]
    )
  end

  def faq_stats_payload
    stats = Captain::AssistantStatsBuilder.new(@assistant).faq_stats
    suggestions = accessible_faq_suggestions(@assistant.faq_suggestions.open).count
    total = stats[:approved] + suggestions
    stats.merge(
      suggestions: suggestions,
      coverage: total.zero? ? 0 : ((stats[:approved] / total.to_f) * 100).round
    )
  end

  def summary_stats_params
    raw = params[:stats]
    return {} if raw.blank?

    raw.permit!.to_h.deep_symbolize_keys
  end

  def summary_cache_key
    stats_digest = Digest::SHA256.hexdigest(summary_stats_params.to_json)
    format('captain_summary:%<account>d:%<assistant>d:%<user>d:%<range>s:%<digest>s',
           account: Current.account.id, assistant: @assistant.id, user: Current.user.id, digest: stats_digest, range: params[:range].to_s)
  end

  def generate_summary
    Captain::OverviewSummaryService.new(
      account: Current.account,
      assistant: @assistant,
      first_name: Current.user.name.to_s.split.first,
      stats: summary_stats_params,
      period: summary_period
    ).perform
  end

  def summary_period
    case params[:range].to_s
    when 'this_month' then { label: 'this month' }
    when 'last_month' then { label: 'last month' }
    else { label: "the last #{%w[7 30 90].include?(params[:range].to_s) ? params[:range] : '7'} days" }
    end
  end

  def playground_response
    history = playground_message_history
    if Current.account.feature_enabled?('captain_integration_v2')
      runner = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'playground')
      history += [{ role: 'user', content: params[:message_content] }] unless latest_message_in_history?(history)
      runner.generate_response(message_history: history)
    else
      Captain::Llm::AssistantChatService.new(assistant: @assistant, source: 'playground')
                                        .generate_response(additional_message: params[:message_content], message_history: history)
    end
  end

  def playground_message_history
    Array(params[:message_history]).map { |entry| entry.permit!.to_h.deep_symbolize_keys }
  end

  def latest_message_in_history?(history)
    last_entry = history.last
    last_entry.present? && last_entry[:role].to_s == 'user' && last_entry[:content] == params[:message_content]
  end
end
