class Captain::Tools::SearchDocumentationService < Captain::Tools::BaseService
  def name
    'search_documentation'
  end

  def description
    'Search and retrieve documentation from knowledge base'
  end

  def parameters
    {
      query: {
        type: 'string',
        description: 'The search query to look up documentation'
      }
    }
  end

  def execute(query:)
    responses = Captain::AssistantResponse.search(query)
    return 'No FAQs found for the given query' if responses.blank?

    responses.map { |response| format_response(response) }.join("\n\n")
  end

  private

  def format_response(response)
    lines = [
      "Question: #{response.question}",
      "Answer: #{response.answer}"
    ]
    source = response.documentable.try(:external_link)
    lines << "Source: #{source}" if source.present?
    lines.join("\n")
  end
end
