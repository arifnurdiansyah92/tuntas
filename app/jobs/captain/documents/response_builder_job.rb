class Captain::Documents::ResponseBuilderJob < ApplicationJob
  queue_as :low

  # FAQ generation from document content lands in the assistant-runtime phase;
  # the enqueue contract is exercised by the document model specs.
  def perform(document); end
end
