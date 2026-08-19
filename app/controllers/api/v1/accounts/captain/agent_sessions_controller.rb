class Api::V1::Accounts::Captain::AgentSessionsController < Api::V1::Accounts::Captain::BaseController
  def show
    message = Current.account.messages.find(params[:id])
    authorize_conversation_access!(message.conversation)

    session = Captain::AgentSession.find_by!(account_id: Current.account.id, result_type: 'Message', result_id: message.id)
    render json: session_json(session, message)
  end

  private

  def authorize_conversation_access!(conversation)
    accessible = Conversations::PermissionFilterService.new(
      Current.account.conversations.where(id: conversation.id), Current.user, Current.account
    ).perform.exists?
    raise Pundit::NotAuthorizedError unless accessible
  end

  def session_json(session, message)
    {
      id: session.id,
      message_id: message.id,
      llm_model: session.llm_model,
      credits_consumed: session.credits_consumed,
      run_context: session.run_context,
      citations: citations_json(session),
      used_faqs: faqs_json(session.used_faq_ids),
      scenarios: scenarios_json(session)
    }
  end

  def citations_json(session)
    documents = Captain::Document.where(account_id: Current.account.id, id: Array(session.cited_document_ids))
    documents.map { |document| { id: document.id, title: document.name, link: document.external_link } }
  end

  def faqs_json(faq_ids)
    Captain::AssistantResponse.where(account_id: Current.account.id, id: Array(faq_ids))
                              .map { |response| { id: response.id, title: response.question } }
  end

  def scenarios_json(session)
    Captain::Scenario.where(account_id: Current.account.id, id: Array(session.scenario_ids))
                     .map { |scenario| { id: scenario.id, title: scenario.title } }
  end
end
