class Captain::Documents::ResponseBuilderJob < ApplicationJob
  queue_as :low

  PDF_PAGES_PER_CHUNK = 5

  def perform(document)
    document.responses.destroy_all
    faqs = generate_faqs(document)
    faqs.each do |faq|
      document.responses.create!(
        assistant: document.assistant,
        question: faq['question'],
        answer: faq['answer']
      )
    end
  end

  private

  def generate_faqs(document)
    return Captain::Llm::FaqGeneratorService.new(document: document).generate unless document.pdf_document?

    generate_pdf_faqs(document)
  end

  def generate_pdf_faqs(document)
    generator = Captain::Llm::PaginatedFaqGeneratorService.new(document, { pages_per_chunk: PDF_PAGES_PER_CHUNK })
    faqs = generator.generate
    document.update!(
      metadata: document.metadata.to_h.merge(
        'faq_generation' => {
          'pages_processed' => generator.total_pages_processed,
          'iterations' => generator.iterations_completed,
          'generated_at' => Time.current.iso8601
        }
      )
    )
    faqs
  end
end
