class Captain::Llm::PdfProcessingService
  def initialize(document)
    @document = document
  end

  def process
    return if @document.openai_file_id.present?

    upload_pdf
  end

  private

  def upload_pdf
    file_id = nil
    @document.pdf_file.blob.open do |file|
      response = openai_client.files.upload(parameters: { file: file, purpose: 'user_data' })
      file_id = response['id']
    end
    raise CustomExceptions::Pdf::UploadError.new(document_id: @document.id) if file_id.blank?

    @document.store_openai_file_id(file_id)
  end

  def openai_client
    @openai_client ||= OpenAI::Client.new(access_token: api_key)
  end

  def api_key
    InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value
  end
end
