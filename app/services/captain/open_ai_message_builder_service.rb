class Captain::OpenAiMessageBuilderService
  def initialize(message:)
    @message = message
  end

  def generate_content
    attachments = @message.attachments
    return @message.content.presence || 'Message without content' if attachments.blank?

    parts = []
    parts << text_part(@message.content) if @message.content.present?
    parts += attachment_parts(attachments)
    return 'Message without content' if parts.blank?

    parts
  end

  private

  def attachment_parts(attachments)
    parts = image_parts(attachments.select(&:image?))

    transcriptions = extract_audio_transcriptions(attachments)
    parts << text_part(transcriptions) if transcriptions.present?

    attachments.reject { |attachment| attachment.image? || attachment.audio? }.each do
      parts << text_part('User has shared an attachment')
    end

    parts
  end

  def image_parts(image_attachments)
    image_attachments.filter_map do |attachment|
      url = get_attachment_url(attachment)
      image_part(url) if url.present?
    end
  end

  def extract_audio_transcriptions(attachments)
    attachments.select(&:audio?).filter_map do |attachment|
      result = Messages::AudioTranscriptionService.new(attachment).perform
      result[:success] ? result[:transcriptions] : nil
    end.join
  end

  def get_attachment_url(attachment)
    return attachment.external_url if attachment.external_url.present?
    return attachment.file_url if attachment.file.attached?

    nil
  end

  def text_part(text)
    { type: 'text', text: text }
  end

  def image_part(url)
    { type: 'image_url', image_url: { url: url } }
  end
end
