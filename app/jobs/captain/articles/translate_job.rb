class Captain::Articles::TranslateJob < ApplicationJob
  queue_as :low

  LANGUAGE_MAP = {
    'pt_BR' => 'Portuguese (Brazil)',
    'zh_CN' => 'Chinese (Simplified)',
    'zh_TW' => 'Chinese (Traditional)',
    'ur_IN' => 'Urdu (India)'
  }.freeze

  def perform(account, article_id, target_locale, target_category_id, user)
    article = account.articles.find(article_id)
    language_name = language_name_for(target_locale)

    translated_title = translate!(account, article.title, language_name, :title)
    translated_content = article.content.presence && translate!(account, article.content, language_name, :content)

    upsert_translation(account, article, target_locale, target_category_id, user, translated_title, translated_content)
  end

  private

  def language_name_for(locale)
    LANGUAGE_MAP[locale.to_s].presence ||
      ISO_639.find(locale.to_s.split('_').first)&.english_name&.split(/[;,]/)&.first&.strip ||
      locale.to_s
  end

  def translate!(account, text, language_name, type)
    result = Captain::Llm::ArticleTranslationService.new(
      account: account, text: text, target_language: language_name, type: type
    ).perform
    raise "Article translation failed: #{result[:error]}" if result[:error].present?

    result[:message]
  end

  def upsert_translation(account, article, target_locale, target_category_id, user, title, content)
    translation = account.articles.find_by(associated_article_id: article.id, locale: target_locale)
    attributes = {
      title: title,
      content: content,
      description: article.description,
      category_id: target_category_id
    }

    if translation
      translation.update!(attributes)
    else
      account.articles.create!(
        attributes.merge(
          portal: article.portal,
          locale: target_locale,
          author_id: user.id,
          status: :draft,
          associated_article_id: article.id
        )
      )
    end
  end
end
