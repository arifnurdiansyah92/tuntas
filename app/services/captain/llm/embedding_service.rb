class Captain::Llm::EmbeddingService
  def self.embedding_model
    InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def initialize(account_id: nil)
    @account_id = account_id
  end

  def get_embedding(content)
    RubyLLM.embed(content, model: self.class.embedding_model).vectors
  end
end
