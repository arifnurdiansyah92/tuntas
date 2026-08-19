class Api::V1::Accounts::Captain::AssistantResponsesController < Api::V1::Accounts::Captain::BaseController
  before_action :set_response, only: [:show, :update, :destroy, :drilldown]
  before_action :check_admin_authorization!, only: [:create, :update, :destroy, :drilldown]

  def index
    responses = filtered_responses
    total_count = responses.count

    render json: {
      payload: paginate(responses.order(id: :desc)).map { |response| response_json(response) },
      meta: pagination_meta(total_count)
    }
  end

  def show
    render json: response_json(@response)
  end

  def create
    response_record = responses_scope.new(response_params)
    response_record.status = :approved
    response_record.save!
    render json: response_json(response_record)
  end

  def update
    @response.assign_attributes(response_params)
    @response.status = :approved if params.dig(:assistant_response, :status).present?
    @response.save!
    render json: response_json(@response)
  end

  def destroy
    @response.destroy!
    head :no_content
  end

  def drilldown
    return head :not_found unless manual_faq?(@response)

    render_conversation_drilldown(answered_sessions_using('used_faq_ids', @response.id))
  end

  private

  def set_response
    @response = responses_scope.find(params[:id])
  end

  def responses_scope
    Captain::AssistantResponse.where(account_id: Current.account.id)
  end

  def filtered_responses
    responses = responses_scope
    responses = responses.where(assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    responses = responses.where(documentable_type: 'Captain::Document', documentable_id: params[:document_id]) if params[:document_id].present?
    search_filter(responses)
  end

  def search_filter(responses)
    return responses if params[:search].blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%"
    responses.where('question ILIKE :term OR answer ILIKE :term', term: term)
  end

  def response_params
    params.require(:assistant_response).permit(:question, :answer, :assistant_id)
  end

  def response_json(response)
    json = response.as_json(only: [:id, :question, :answer, :status, :account_id, :created_at, :updated_at])
    json['assistant'] = { 'id' => response.assistant_id }
    json['documentable'] = documentable_json(response)
    json['used_in_conversations_count'] = usage_count(response) if expose_usage?(response)
    json
  end

  def documentable_json(response)
    return if response.documentable_id.blank?

    { 'id' => response.documentable_id, 'type' => response.documentable_type }
  end

  def expose_usage?(response)
    Current.account_user.administrator? && manual_faq?(response)
  end

  # Only FAQs authored by a person track conversation usage; document-generated
  # FAQs and approved suggestions are covered by document usage stats instead.
  def manual_faq?(response)
    response.documentable_type == 'User'
  end

  def usage_count(response)
    answered_sessions_using('used_faq_ids', response.id)
      .where(subject_id: Current.account.conversations.select(:id))
      .distinct
      .count(:subject_id)
  end
end
