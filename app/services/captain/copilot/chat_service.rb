class Captain::Copilot::ChatService
  DEFAULT_TEMPERATURE = 0.5

  COPILOT_TOOLS = [
    Captain::Tools::Copilot::GetConversationService,
    Captain::Tools::Copilot::SearchConversationsService,
    Captain::Tools::Copilot::GetContactService,
    Captain::Tools::Copilot::SearchContactsService,
    Captain::Tools::Copilot::GetArticleService,
    Captain::Tools::Copilot::SearchArticlesService,
    Captain::Tools::Copilot::SearchLinearIssuesService
  ].freeze

  attr_reader :assistant, :account, :user, :copilot_thread, :previous_history, :messages

  def initialize(assistant, config = {})
    @assistant = assistant
    @account = assistant.account
    @config = config
    setup_user
    setup_history
    @messages = build_messages
  end

  def generate_response(input)
    @messages << { role: 'user', content: input } if input.present?
    response = request_chat_completion
    persist_message(response) if copilot_thread.present? && response.present?
    increment_response_usage
    response
  end

  private

  def setup_user
    @user = account.users.find_by(id: @config[:user_id]) if @config[:user_id].present?
  end

  def setup_history
    @copilot_thread = account.copilot_threads.find_by(id: @config[:copilot_thread_id]) if @config[:copilot_thread_id].present?

    @previous_history =
      if copilot_thread.present?
        copilot_thread.copilot_messages.order(:created_at, :id).map do |message|
          { role: message.message_type, content: message.message['content'] }
        end
      else
        Array(@config[:previous_history])
      end
  end

  def build_messages
    built = [
      { role: 'system', content: system_prompt },
      { role: 'system', content: account_context }
    ]
    built += previous_history
    viewing_context = current_viewing_context
    built << viewing_context if viewing_context.present?
    built
  end

  def system_prompt
    Captain::Llm::SystemPromptsService.copilot(assistant.name, tool_registry.tools_summary.presence)
  end

  def tool_registry
    @tool_registry ||= Captain::ToolRegistryService.new(assistant, user: user).tap do |registry|
      COPILOT_TOOLS.each { |tool_class| registry.register_tool(tool_class) }
    end
  end

  def account_context
    "You are assisting agents on the account with ID #{account.id} (#{account.name}). " \
      'All lookups are scoped to this account.'
  end

  def current_viewing_context
    conversation = viewable_conversation
    return if conversation.blank?

    {
      role: 'system',
      content: "You are currently viewing the conversation ##{conversation.display_id} " \
               "with the contact #{conversation.contact.name} (contact id: #{conversation.contact.id}). " \
               'Questions without further context usually refer to this conversation.'
    }
  end

  def viewable_conversation
    return if user.blank? || @config[:conversation_id].blank?

    conversation = account.conversations.find_by(display_id: @config[:conversation_id])
    return if conversation.blank?

    accessible = Conversations::PermissionFilterService.new(
      account.conversations.where(id: conversation.id), user, account
    ).perform.exists?
    conversation if accessible
  end

  def request_chat_completion
    chat = build_chat
    history = @messages.dup
    current = history.pop
    history.each { |message| chat.add_message(role: message[:role].to_sym, content: message[:content]) }
    parse_response(chat.ask(current[:content]).content)
  end

  def build_chat
    model = Llm::FeatureRouter.resolve(feature: 'copilot', account: account).fetch(:model)
    RubyLLM.chat(model: model)
           .with_temperature(DEFAULT_TEMPERATURE)
           .with_params(response_format: { type: 'json_object' })
  end

  def parse_response(content)
    return content if content.is_a?(Hash)

    JSON.parse(content)
  rescue JSON::ParserError
    { 'content' => content }
  end

  def persist_message(response)
    copilot_thread.copilot_messages.create!(
      account: account,
      message_type: :assistant,
      message: response
    )
  end

  def increment_response_usage
    usage = account.custom_attributes['captain_responses_usage'].to_i + 1
    account.custom_attributes['captain_responses_usage'] = usage
    account.save!
  end
end
