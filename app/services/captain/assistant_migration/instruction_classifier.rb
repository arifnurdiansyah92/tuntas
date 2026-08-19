class Captain::AssistantMigration::InstructionClassifier
  DRAFT_CATEGORIES = %i[response_guidelines guardrails scenario_candidates faq_document_candidates needs_review].freeze
  CATEGORY_LIMITS = {
    response_guidelines: 15,
    guardrails: 15,
    scenario_candidates: 10,
    faq_document_candidates: 25,
    needs_review: 10
  }.freeze

  def initialize(assistant:)
    @assistant = assistant
  end

  def perform
    generated = classify
    auditor_output = audit(generated)
    audited_payload(generated, auditor_output)
  end

  private

  def classify
    response = build_chat(Captain::AssistantMigration::InstructionClassifierSchema)
               .with_instructions(Captain::PromptRenderer.render('instruction_classifier'))
               .ask(classification_input)
    symbolized_draft(response.content)
  end

  def audit(generated_draft)
    capacities = remaining_capacities(generated_draft)
    return {} if capacities.values.all? { |capacity| capacity <= 0 }

    schema = Captain::AssistantMigration::InstructionAuditorSchema.for(**capacities)
    response = build_chat(schema)
               .with_instructions(Captain::PromptRenderer.render('instruction_auditor'))
               .ask(audit_input(generated_draft, capacities))
    symbolized_draft(response.content)
  end

  # Coverage additions from the auditor are appended to the generated draft;
  # existing draft content is never replaced.
  def audited_payload(generated_draft, auditor_output)
    result = generated_draft.deep_dup
    DRAFT_CATEGORIES.each do |category|
      additions = Array(auditor_output[category])
      next if additions.blank?

      result[category] = Array(result[category]) + additions
    end
    result
  end

  def remaining_capacities(generated_draft)
    CATEGORY_LIMITS.each_with_object({}) do |(category, limit), memo|
      memo[category] = limit - Array(generated_draft[category]).size
    end
  end

  def build_chat(schema)
    model = Llm::FeatureRouter.resolve(feature: 'assistant', account: @assistant.account).fetch(:model)
    RubyLLM.chat(model: model).with_temperature(0).with_schema(schema)
  end

  def classification_input
    <<~INPUT
      <custom_instructions>
      #{@assistant.config['instructions']}
      </custom_instructions>
    INPUT
  end

  def audit_input(generated_draft, capacities)
    <<~INPUT
      <custom_instructions>
      #{@assistant.config['instructions']}
      </custom_instructions>

      <generated_draft>
      #{JSON.pretty_generate(generated_draft)}
      </generated_draft>

      <available_additions>
      #{JSON.generate(capacities.select { |_category, capacity| capacity.positive? })}
      </available_additions>
    INPUT
  end

  def symbolized_draft(content)
    parsed = content.is_a?(Hash) ? content : JSON.parse(content.to_s)
    parsed.deep_symbolize_keys
  rescue JSON::ParserError
    {}
  end
end
