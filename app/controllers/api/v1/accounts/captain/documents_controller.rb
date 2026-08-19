class Api::V1::Accounts::Captain::DocumentsController < Api::V1::Accounts::Captain::BaseController
  before_action :set_document, only: [:show, :destroy, :sync, :drilldown]
  before_action :check_admin_authorization!, only: [:create, :destroy, :sync, :drilldown]
  before_action -> { check_admin_authorization! }, only: [:index], if: -> { params[:sort] == 'most_used' }

  def index
    documents = documents_scope
    documents = documents.where(assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    total_count = documents.count
    page_documents = paginated_documents(documents)

    render json: {
      payload: documents_payload(page_documents),
      meta: pagination_meta(total_count)
    }
  end

  def show
    render json: document_json(@document)
  end

  def create
    return render json: { error: 'Document limit reached for the current plan' }, status: :unprocessable_entity if document_limit_exceeded?

    document = Current.account.captain_documents.create!(document_params)
    render json: document_json(document)
  end

  def destroy
    @document.destroy!
    head :no_content
  end

  def sync
    return render json: { error: 'This document cannot be synced' }, status: :unprocessable_entity unless @document.syncable?

    enqueue_document_sync(@document)
    head :accepted
  end

  def drilldown
    render_conversation_drilldown(answered_sessions_using('document_ids', @document.id))
  end

  private

  def set_document
    @document = documents_scope.find(params[:id])
  end

  # Documents are reached through the account's assistants: legacy rows created
  # before account backfilling still belong to the assistant's account.
  def documents_scope
    Captain::Document.joins(:assistant).where(captain_assistants: { account_id: Current.account.id })
  end

  def document_params
    params.require(:document).permit(:name, :external_link, :assistant_id, :pdf_file)
  end

  def paginated_documents(documents)
    ordered =
      if params[:sort] == 'most_used'
        documents.sort_by { |document| -usage_counts[document.id].to_i }
      else
        documents.order(id: :desc)
      end
    ordered.is_a?(Array) ? ordered[(page - 1) * RESULTS_PER_PAGE, RESULTS_PER_PAGE].to_a : paginate(ordered)
  end

  def documents_payload(page_documents)
    response_counts = Captain::AssistantResponse.where(account_id: Current.account.id, documentable_type: 'Captain::Document',
                                                       documentable_id: page_documents.map(&:id))
                                                .group(:documentable_id).count

    page_documents.map do |document|
      json = document_json(document).merge('responses_count' => response_counts.fetch(document.id, 0))
      json['used_in_conversations_count'] = usage_counts[document.id].to_i if Current.account_user.administrator?
      json
    end
  end

  def usage_counts
    @usage_counts ||= answered_session_rows
                      .each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |(document_ids, conversation_id), memo|
                        Array(document_ids).each { |document_id| memo[document_id] << conversation_id }
                      end
                      .transform_values(&:size)
  end

  def answered_session_rows
    Captain::AgentSession
      .where(account_id: Current.account.id, subject_type: 'Conversation')
      .where('credits_consumed > 0')
      .where(subject_id: Current.account.conversations.select(:id))
      .pluck(:document_ids, :subject_id)
  end

  def document_json(document)
    document.as_json(only: [:id, :name, :external_link, :content, :status, :assistant_id, :account_id, :created_at, :updated_at])
            .merge(
              'assistant' => { 'id' => document.assistant_id },
              'sync_status' => document.sync_status,
              'last_synced_at' => document.last_synced_at&.to_i,
              'last_sync_error_code' => document.last_sync_error_code
            )
  end

  def enqueue_document_sync(document)
    # rubocop:disable Rails/SkipsModelValidations
    document.update_columns(sync_status: Captain::Document.sync_statuses[:syncing], last_sync_attempted_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    Captain::Documents::PerformSyncJob.set(queue: :low).perform_later(document)
  end

  def document_limit_exceeded?
    limit = plan_document_limit
    limit.present? && documents_scope.count >= limit.to_i
  end

  def plan_document_limit
    limits = JSON.parse(InstallationConfig.find_by(name: 'CAPTAIN_CLOUD_PLAN_LIMITS')&.value.presence || '{}')
    plan = Current.account.custom_attributes['plan_name'].to_s.downcase
    limits.dig(plan, 'documents')
  rescue JSON::ParserError
    nil
  end
end
