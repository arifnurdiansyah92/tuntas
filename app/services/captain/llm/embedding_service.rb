class Captain::Llm::EmbeddingService
  DEFAULT_MODEL = 'text-embedding-3-small'.freeze

  def get_embedding(content, model: DEFAULT_MODEL)
    response = HTTParty.post(
      "#{api_base}/embeddings",
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_key}"
      },
      body: { input: content, model: model }.to_json
    )
    raise "Embedding request failed with status #{response.code}" unless response.success?

    response.parsed_response.dig('data', 0, 'embedding')
  end

  private

  def api_key
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end

  def api_base
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com'
    "#{endpoint.chomp('/')}/v1"
  end
end
