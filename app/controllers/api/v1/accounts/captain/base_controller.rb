class Api::V1::Accounts::Captain::BaseController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  private

  def check_admin_authorization!
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  def page
    (params[:page].presence || 1).to_i
  end

  def pagination_meta(total_count)
    { page: page, total_count: total_count }
  end

  def paginate(scope)
    scope.offset((page - 1) * RESULTS_PER_PAGE).limit(RESULTS_PER_PAGE)
  end

  def accessible_conversations
    Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform
  end

  # Shared drilldown contract: distinct live conversations referenced by the
  # given agent-session scope, newest activity first.
  def render_conversation_drilldown(session_scope)
    conversations = Current.account.conversations.where(id: session_scope.select(:subject_id)).order(last_activity_at: :desc)
    per_page = (params[:per_page].presence || RESULTS_PER_PAGE).to_i
    current_page = (params[:page].presence || 1).to_i
    total_count = conversations.count

    render json: {
      payload: conversations.offset((current_page - 1) * per_page).limit(per_page).map do |conversation|
        { record_type: 'conversation', conversation: drilldown_conversation_json(conversation) }
      end,
      meta: { current_page: current_page, per_page: per_page, total_count: total_count, conversation_count: total_count }
    }
  end

  def drilldown_conversation_json(conversation)
    conversation.as_json(only: [:id, :display_id, :status, :last_activity_at, :inbox_id, :contact_id])
  end

  def answered_sessions_using(column, record_id)
    Captain::AgentSession.where(account_id: Current.account.id, subject_type: 'Conversation')
                         .where('credits_consumed > 0')
                         .where("#{column} @> ?", [record_id].to_json)
  end

  # Suggestions are visible when at least one source conversation is accessible
  # to the user; suggestions without recorded sources stay visible to everyone
  # who can see the assistant.
  def accessible_faq_suggestions(scope)
    backed_ids = scope.joins(:observations)
                      .where(captain_faq_observations: { conversation_id: accessible_conversations.select(:id) })
                      .distinct.ids
    unbacked_ids = scope.where.missing(:observations).ids

    scope.where(id: backed_ids | unbacked_ids)
  end
end
