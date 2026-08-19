class Captain::AssistantMigration::DraftApplier
  DESCRIPTION_LIMIT = 500

  def initialize(assistant:, draft:, dry_run: true)
    @assistant = assistant
    @draft = draft.deep_stringify_keys
    @dry_run = dry_run
  end

  def perform
    validate_faq_candidates!
    validate_description!

    changes = build_changes
    apply!(changes) unless @dry_run

    { changes: changes, dry_run: @dry_run }
  end

  private

  def validate_faq_candidates!
    valid = faq_candidates.all? { |candidate| candidate.is_a?(Hash) && candidate['question'].present? && candidate['answer'].present? }
    raise ArgumentError, 'FAQ document candidates must be question and answer objects' unless valid

    known_answers = existing_faq_answers
    faq_candidates.each do |candidate|
      question = normalize_question(candidate['question'])
      if known_answers.key?(question) && known_answers[question] != candidate['answer']
        raise ArgumentError, "FAQ candidate conflicts with an existing FAQ: #{question}"
      end

      known_answers[question] = candidate['answer'] unless known_answers.key?(question)
    end
  end

  def validate_description!
    raise ArgumentError, "Assistant description exceeds #{DESCRIPTION_LIMIT} characters" if new_description.length > DESCRIPTION_LIMIT
  end

  def build_changes
    {
      description: { from: @assistant.description, to: new_description.presence || @assistant.description },
      response_guidelines: { from: current_guidelines, to: new_guidelines },
      guardrails: { from: current_guardrails, to: new_guardrails },
      config: { from: @assistant.config, to: new_config },
      faq_responses: { create: creatable_faq_candidates }
    }
  end

  def apply!(changes)
    @assistant.update!(
      description: changes.dig(:description, :to),
      response_guidelines: changes.dig(:response_guidelines, :to),
      guardrails: changes.dig(:guardrails, :to),
      config: changes.dig(:config, :to)
    )
    changes.dig(:faq_responses, :create).each do |candidate|
      @assistant.responses.create!(
        account_id: @assistant.account_id,
        question: candidate['question'],
        answer: candidate['answer'],
        status: :approved
      )
    end
  end

  def new_config
    @assistant.config.deep_dup.merge(
      'assistant_migration' => {
        'scenario_candidates' => scenario_candidates,
        'faq_document_candidates' => faq_candidates,
        'needs_review' => Array(@draft['needs_review']),
        'original_values' => original_values
      }
    )
  end

  def original_values
    {
      'name' => @assistant.name,
      'description' => @assistant.description,
      'config' => @assistant.config.deep_dup,
      'response_guidelines' => current_guidelines,
      'guardrails' => current_guardrails
    }
  end

  def new_description
    @new_description ||= Array(@draft['business_product_context']).join("\n\n")
  end

  def new_guidelines
    scenario_guidelines = scenario_candidates.filter_map { |candidate| candidate['response_guideline'].presence }
    (current_guidelines + Array(@draft['response_guidelines']) + scenario_guidelines).uniq
  end

  def new_guardrails
    (current_guardrails + Array(@draft['guardrails'])).uniq
  end

  def current_guidelines
    Array(@assistant.response_guidelines)
  end

  def current_guardrails
    Array(@assistant.guardrails)
  end

  def scenario_candidates
    Array(@draft['scenario_candidates'])
  end

  def faq_candidates
    Array(@draft['faq_document_candidates'])
  end

  def creatable_faq_candidates
    existing = existing_faq_answers
    faq_candidates.reject { |candidate| existing.key?(normalize_question(candidate['question'])) }
                  .map { |candidate| candidate.merge('status' => 'approved') }
  end

  def existing_faq_answers
    @assistant.responses.each_with_object({}) do |response, memo|
      memo[normalize_question(response.question)] = response.answer
    end
  end

  def normalize_question(question)
    question.to_s.gsub(/\s+/, ' ').strip
  end
end
