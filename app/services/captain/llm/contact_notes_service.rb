class Captain::Llm::ContactNotesService
  NOTES_LIMIT = 5

  def initialize(assistant, conversation)
    @assistant = assistant
    @conversation = conversation
    @contact = conversation.contact
  end

  def generate_and_update_notes
    return if transcript.blank?

    notes = generate_notes
    return if notes.blank?

    notes.first(NOTES_LIMIT).each do |note_content|
      next if note_content.blank? || duplicate_note?(note_content)

      @contact.notes.create!(account_id: @conversation.account_id, content: note_content)
    end
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: @conversation.account).capture_exception
    nil
  end

  private

  def generate_notes
    model = Llm::FeatureRouter.resolve(feature: 'assistant', account: @assistant.account).fetch(:model)
    chat = RubyLLM.chat(model: model)
                  .with_temperature(0.2)
                  .with_params(response_format: { type: 'json_object' })
                  .with_instructions(system_prompt)

    response = chat.ask("<conversation_transcript>\n#{transcript}\n</conversation_transcript>")
    parse_notes(response.content)
  end

  def system_prompt
    <<~PROMPT
      You extract durable facts about a customer from a resolved support conversation so future
      conversations have context. Capture only stable, reusable facts (product plan, environment,
      preferences, commitments made) — never transient conversation details.

      Return strictly valid JSON: {"notes": ["..."]}. Return {"notes": []} when nothing durable was learned.
    PROMPT
  end

  def parse_notes(content)
    parsed = content.is_a?(Hash) ? content : JSON.parse(content)
    Array(parsed['notes']).map(&:to_s)
  rescue JSON::ParserError
    []
  end

  def transcript
    @transcript ||= @conversation.messages
                                 .where(message_type: [:incoming, :outgoing], private: false)
                                 .order(:created_at)
                                 .filter_map { |message| "#{message.incoming? ? 'Customer' : 'Agent'}: #{message.content}" if message.content.present? }
                                 .join("\n")
  end

  def duplicate_note?(content)
    @existing_notes ||= @contact.notes.pluck(:content)
    @existing_notes.any? { |existing| existing.to_s.strip.casecmp?(content.strip) }
  end
end
