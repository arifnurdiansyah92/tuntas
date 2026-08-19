class Captain::Tools::Copilot::SearchArticlesService < Captain::Tools::BaseService
  RESULT_LIMIT = 25

  def name
    'search_articles'
  end

  def description
    'Search articles based on parameters'
  end

  def parameters
    {
      query: {
        type: 'string',
        description: 'Search term matched against article title and content'
      },
      category_id: {
        type: 'number',
        description: 'Filter articles by category ID'
      },
      status: {
        type: 'string',
        description: 'Filter articles by status (draft, published, archived)'
      }
    }
  end

  def execute(query: nil, category_id: nil, status: nil)
    articles = filtered_articles(query, category_id, status).limit(RESULT_LIMIT)
    return 'No articles found' if articles.blank?

    sections = ["Total number of articles: #{articles.size}"]
    sections += articles.map(&:to_llm_text)
    sections.join("\n\n")
  end

  def active?
    user_has_permission?('knowledge_base_manage')
  end

  private

  def filtered_articles(query, category_id, status)
    articles = account.articles
    articles = articles.where(category_id: category_id) if category_id.present?
    articles = articles.where(status: status) if status.present? && Article.statuses.key?(status.to_s)
    articles = articles.text_search(query) if query.present?
    articles
  end
end
