class Api::V1::Accounts::Captain::FaqSuggestionsController < Api::V1::Accounts::Captain::BaseController
  before_action :set_suggestion, only: [:show, :update, :approve, :dismiss]

  def index
    suggestions = accessible_faq_suggestions(suggestions_scope.open.where(assistant_id: params[:assistant_id]))
    total_count = suggestions.count

    render json: {
      payload: paginate(suggestions.order(id: :desc)).map { |suggestion| suggestion_json(suggestion) },
      meta: pagination_meta(total_count)
    }
  end

  def show
    render json: suggestion_json(@suggestion).merge(observations: observations_json(@suggestion))
  end

  def update
    @suggestion.update!(suggestion_params)
    render json: suggestion_json(@suggestion)
  end

  def approve
    @suggestion.update!(suggestion_params) if suggestion_params.present?
    @suggestion.assistant.responses.create!(
      account_id: Current.account.id,
      question: @suggestion.question,
      answer: @suggestion.answer,
      status: :approved
    )
    @suggestion.approved!
    render json: suggestion_json(@suggestion)
  end

  def dismiss
    @suggestion.dismissed!
    render json: suggestion_json(@suggestion)
  end

  private

  def set_suggestion
    @suggestion = accessible_faq_suggestions(suggestions_scope).find(params[:id])
  end

  def suggestions_scope
    Captain::FaqSuggestion.where(account_id: Current.account.id)
  end

  def suggestion_params
    return {} if params[:faq_suggestion].blank?

    params.require(:faq_suggestion).permit(:question, :answer)
  end

  def suggestion_json(suggestion)
    suggestion.as_json(only: [:id, :question, :answer, :status, :language, :source_count, :assistant_id, :account_id, :created_at, :updated_at])
  end

  def observations_json(suggestion)
    accessible_ids = accessible_conversations.pluck(:id)
    suggestion.observations.includes(:conversation).filter_map do |observation|
      next unless accessible_ids.include?(observation.conversation_id)

      {
        id: observation.id,
        conversation: observation.conversation.as_json(only: [:id, :display_id, :status, :inbox_id])
      }
    end
  end
end
