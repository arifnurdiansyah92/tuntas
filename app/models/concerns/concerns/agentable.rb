module Concerns::Agentable
  extend ActiveSupport::Concern

  DEFAULT_TEMPERATURE = 0.5
  CAPTAIN_V2_DEFAULT_MODEL = 'gpt-5.2'.freeze

  def agent
    Agents::Agent.new(
      name: agent_name,
      instructions: method(:agent_instructions).to_proc,
      tools: agent_tools,
      model: agent_model,
      temperature: agent_temperature,
      response_schema: agent_response_schema
    )
  end

  def agent_instructions(run_context = nil)
    context = prompt_context
    context = context.merge(run_context_state(run_context)) if run_context
    Captain::PromptRenderer.render(template_name, context)
  end

  private

  def run_context_state(run_context)
    state = run_context.context[:state] || {}
    {
      conversation: state[:conversation] || {},
      contact: state[:contact],
      campaign: state[:campaign] || {}
    }
  end

  def agent_name
    raise NotImplementedError, "#{self.class.name} must implement agent_name"
  end

  def prompt_context
    raise NotImplementedError, "#{self.class.name} must implement prompt_context"
  end

  def agent_tools
    []
  end

  def agent_temperature
    value = respond_to?(:temperature) ? temperature : nil
    (value.presence || DEFAULT_TEMPERATURE).to_f
  end

  def agent_model
    return Llm::Models.default_model_for('assistant') if account.blank?
    return CAPTAIN_V2_DEFAULT_MODEL if account.feature_enabled?('captain_integration_v2')

    account_override = account.captain_models&.dig('assistant')
    return account_override if account_override.present?

    installation_model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    installation_model.presence || Llm::Models.default_model_for('assistant')
  end

  def template_name
    self.class.name.underscore
  end

  def agent_response_schema
    Captain::ResponseSchema
  end
end
