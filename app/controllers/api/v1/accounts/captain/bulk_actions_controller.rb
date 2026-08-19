class Api::V1::Accounts::Captain::BulkActionsController < Api::V1::Accounts::Captain::BaseController
  before_action :check_admin_authorization!
  before_action :validate_bulk_params!

  def create
    case [params[:type], params.dig(:fields, :status)]
    when %w[AssistantResponse delete]
      delete_responses
    when %w[AssistantDocument delete]
      delete_documents
    when %w[AssistantDocument sync]
      sync_documents
    else
      render_invalid_action
    end
  end

  private

  def validate_bulk_params!
    return if params[:type].present? && Array(params[:ids]).any? && params.dig(:fields, :status).present?

    render_invalid_action
  end

  def render_invalid_action
    render json: { success: false, error: 'Unsupported bulk action' }, status: :unprocessable_entity
  end

  def bulk_ids
    Array(params[:ids])
  end

  def delete_responses
    Captain::AssistantResponse.where(account_id: Current.account.id, id: bulk_ids).destroy_all
    render json: []
  end

  def delete_documents
    documents = Current.account.captain_documents.where(id: bulk_ids)
    count = documents.count
    documents.destroy_all
    render json: { count: count }
  end

  def sync_documents
    synced_ids = Current.account.captain_documents.where(id: bulk_ids).filter_map do |document|
      next unless document.syncable?

      # rubocop:disable Rails/SkipsModelValidations
      document.update_columns(sync_status: Captain::Document.sync_statuses[:syncing], last_sync_attempted_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
      Captain::Documents::PerformSyncJob.set(queue: :low).perform_later(document)
      document.id
    end

    render json: { ids: synced_ids, count: synced_ids.size }
  end
end
