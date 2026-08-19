class Messages::AudioTranscriptionService
  TRANSCRIPTION_MODEL = 'whisper-1'.freeze

  def initialize(attachment)
    @attachment = attachment
  end

  def perform
    return failure if api_key.blank? || !@attachment.audio?

    transcription = cached_transcription || transcribe_audio
    return failure if transcription.blank?

    { success: true, transcriptions: transcription }
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: @attachment.account).capture_exception
    failure
  end

  private

  def failure
    { success: false, transcriptions: nil }
  end

  def cached_transcription
    @attachment.meta&.[]('transcribed_text').presence if @attachment.respond_to?(:meta)
  end

  def transcribe_audio
    return if @attachment.file.blank? || !@attachment.file.attached?

    @attachment.file.blob.open do |file|
      response = client.audio.transcribe(parameters: { model: TRANSCRIPTION_MODEL, file: file })
      response['text'].presence
    end
  end

  def client
    @client ||= OpenAI::Client.new(access_token: api_key)
  end

  def api_key
    @api_key ||= InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence || ENV.fetch('OPENAI_API_KEY', nil)
  end
end
