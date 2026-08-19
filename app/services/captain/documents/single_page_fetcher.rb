class Captain::Documents::SinglePageFetcher
  Result = Struct.new(:success, :title, :content, :error_code, keyword_init: true)

  def initialize(document)
    @document = document
  end

  def fetch
    crawler = Captain::Tools::SimplePageCrawlService.new(@document.external_link)
    unless crawler.success?
      error_code = crawler.status_code == 404 ? 'not_found' : 'fetch_failed'
      return Result.new(success: false, error_code: error_code)
    end

    Result.new(success: true, title: crawler.page_title, content: crawler.body_markdown)
  end
end
