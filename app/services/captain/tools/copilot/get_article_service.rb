class Captain::Tools::Copilot::GetArticleService < Captain::Tools::BaseService
  def name
    'get_article'
  end

  def description
    'Get details of an article including its content and metadata'
  end

  def parameters
    {
      article_id: {
        type: 'number',
        description: 'The ID of the article to fetch'
      }
    }
  end

  def execute(article_id: nil)
    article = account.articles.find_by(id: article_id) if article_id.present?
    return 'Article not found' if article.blank?

    article.to_llm_text
  end

  def active?
    user_has_permission?('knowledge_base_manage')
  end
end
