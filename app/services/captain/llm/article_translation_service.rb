class Captain::Llm::ArticleTranslationService < Captain::BaseTaskService
  pattr_initialize [:account!, :text!, :target_language!, :type!]

  TITLE_PROMPT_TEMPLATE = <<~PROMPT.freeze
    You are a professional translator for a customer help center.
    Translate the given article title into %<language>s. Return only the translated title.
  PROMPT

  CONTENT_PROMPT_TEMPLATE = <<~PROMPT.freeze
    You are a professional translator for a customer help center working with markdown documents.
    Translate the given markdown article into %<language>s.
    Preserve ALL HTML tags, markdown structure, links, and code blocks exactly as they appear.
    Return only the translated markdown.
  PROMPT

  def perform
    result = make_api_call(
      feature: 'help_center_article_generation',
      model: model,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: text }
      ]
    )
    return result if result[:message].blank?

    result.merge(message: result[:message].strip)
  end

  private

  def event_name
    'article_translation'
  end

  def system_prompt
    case type.to_sym
    when :title
      format(TITLE_PROMPT_TEMPLATE, language: target_language)
    when :content
      format(CONTENT_PROMPT_TEMPLATE, language: target_language)
    else
      raise ArgumentError, "Invalid type: #{type}"
    end
  end

  def model
    account.captain_models&.dig('help_center_article_generation').presence ||
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
      Llm::Config::DEFAULT_MODEL
  end
end
