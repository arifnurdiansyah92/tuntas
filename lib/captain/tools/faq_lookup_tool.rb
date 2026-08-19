class Captain::Tools::FaqLookupTool < Captain::Tools::BasePublicTool
  RESULT_LIMIT = 5

  description 'Search FAQ responses using semantic similarity to find relevant answers'
  param :query, type: 'string', desc: 'The question or topic to search for in the FAQ database'

  def perform(tool_context, query:)
    log_tool_usage('searching', { query: query })

    responses = search_responses(query)
    if responses.blank?
      log_tool_usage('no_results', { query: query })
      return "No relevant FAQs found for: #{query}"
    end

    log_tool_usage('found_results', { query: query, count: responses.size })
    record_metadata(tool_context.state, responses)
    format_responses(tool_context.state, responses)
  end

  private

  def search_responses(query)
    embedding = Captain::Llm::EmbeddingService.new.get_embedding(query)
    assistant.responses.approved
             .nearest_neighbors(:embedding, embedding, distance: 'cosine')
             .limit(RESULT_LIMIT).to_a
  end

  def record_metadata(state, responses)
    metadata = (state[:cw_metadata] ||= {})
    append_metadata(metadata, :faq_ids, responses.map(&:id))
    append_metadata(metadata, :used_faq_ids, responses.select { |response| response.documentable_type == 'User' }.map(&:id))
    append_metadata(metadata, :document_ids,
                    responses.select { |response| response.documentable_type == 'Captain::Document' }.map(&:documentable_id))
  end

  def append_metadata(metadata, key, ids)
    return if ids.empty?

    metadata[key] = ((metadata[key] || []) + ids).uniq
  end

  def format_responses(state, responses)
    responses.map { |response| format_response(state, response) }.join("\n\n")
  end

  def format_response(state, response)
    text = "Question: #{response.question}\nAnswer: #{response.answer}"
    citation_index = citation_index_for(state, response)
    text += "\nCitation index: #{citation_index}" if citation_index
    text
  end

  def citation_index_for(state, response)
    return unless assistant.config['feature_citation']

    document = response.documentable
    return unless document.is_a?(Captain::Document)
    return if document.pdf_document?
    return if document.customer_visible_source_url.blank?

    sources = (state[Captain::Assistant::CITATION_SOURCES_STATE_KEY] ||= {})
    existing_index = sources.key(document.id)
    return existing_index if existing_index

    next_index = sources.keys.max.to_i + 1
    sources[next_index] = document.id
    next_index
  end
end
