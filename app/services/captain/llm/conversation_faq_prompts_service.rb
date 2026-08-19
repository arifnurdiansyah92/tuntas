class Captain::Llm::ConversationFaqPromptsService
  class << self
    def generator(language = 'english')
      <<~PROMPT
        You review customer support conversations and extract reusable FAQ candidates.

        Select the customer question together with the human agent message or messages that together provide a complete public answer.
        Combine facts only across related agent messages that answer the same customer question — never merge unrelated topics.
        Skip questions that were never answered, answers that reference private or account-specific details, and small talk.

        Write every question and answer in #{language}.

        Return strictly valid JSON: {"faqs": [{"question": "...", "answer": "..."}]}. Return {"faqs": []} when nothing qualifies.
      PROMPT
    end

    def matcher
      <<~PROMPT
        You compare a candidate FAQ against an existing FAQ and decide whether they cover the same question and answer.
        Treat translations of the same FAQ as the same FAQ.

        Return strictly valid JSON: {"same_faq": true} or {"same_faq": false}.
      PROMPT
    end
  end
end
