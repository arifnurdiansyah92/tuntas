class Api::V1::Accounts::AppliedSlasController < Api::V1::Accounts::BaseController
  before_action :check_sla_feature_enabled
  before_action :check_authorization
  before_action :set_applied_slas

  def index
    @applied_slas = @applied_slas.where(sla_status: [:missed, :active_with_misses])
                                 .includes(:sla_policy, conversation: [:contact, :assignee, :inbox])
    @applied_slas = @applied_slas.where(conversations: { assignee_id: params[:agent_ids] }) if params[:agent_ids].present?
  end

  def metrics
    total = @applied_slas.count
    misses = @applied_slas.where(sla_status: [:missed, :active_with_misses]).count
    hit_rate = misses.zero? ? '100%' : "#{((total - misses) * 100.0 / total).round(2)}%"

    render json: { total_applied_slas: total, number_of_sla_misses: misses, hit_rate: hit_rate }
  end

  def download
    breached = @applied_slas.where(sla_status: [:missed, :active_with_misses])
                            .includes(:sla_policy, conversation: [:assignee])

    response.headers['Content-Disposition'] = 'attachment; filename=breached_conversation.csv'
    render plain: generate_csv(breached)
    # assign after render so Rails does not append a charset to the header
    response.headers['Content-Type'] = 'text/csv'
  end

  private

  def check_sla_feature_enabled
    render json: { error: 'SLA feature is not enabled' }, status: :unauthorized unless Current.account.feature_enabled?('sla')
  end

  def set_applied_slas
    @applied_slas = Current.account.applied_slas.with_sla_applicable_conversation
    @applied_slas = @applied_slas.where(sla_policy_id: params[:sla_policy_id]) if params[:sla_policy_id].present?
    filter_by_created_range
    filter_by_labels
  end

  def filter_by_created_range
    @applied_slas = @applied_slas.where(applied_slas: { created_at: Time.zone.at(params[:since].to_i).. }) if params[:since].present?
    @applied_slas = @applied_slas.where(applied_slas: { created_at: ..Time.zone.at(params[:until].to_i) }) if params[:until].present?
  end

  def filter_by_labels
    return if params[:label_list].blank?

    conversation_ids = Current.account.conversations.tagged_with(params[:label_list], any: true).pluck(:id)
    @applied_slas = @applied_slas.where(conversation_id: conversation_ids)
  end

  def generate_csv(breached_applied_slas)
    CSV.generate do |csv|
      csv << ['Conversation Id', 'Sla Policy Breached', 'Conversation Status', 'Assignee', 'Created At']
      breached_applied_slas.each do |applied_sla|
        conversation = applied_sla.conversation
        csv << [
          conversation.display_id,
          applied_sla.sla_policy.name,
          conversation.status,
          conversation.assignee&.name,
          applied_sla.created_at
        ]
      end
    end
  end
end
