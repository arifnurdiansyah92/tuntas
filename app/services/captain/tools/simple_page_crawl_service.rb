class Captain::Tools::SimplePageCrawlService
  def initialize(url)
    @url = url
  end

  def success?
    response.code.between?(200, 299)
  end

  def status_code
    response.code
  end

  def page_title
    return if sitemap?

    parsed_html.at_css('title')&.text&.strip.presence
  end

  def body_markdown
    return if sitemap?

    body = parsed_html.at_css('body')
    return if body.blank?

    ReverseMarkdown.convert(body, unknown_tags: :bypass, github_flavored: true)
  end

  def meta_description
    return if sitemap?

    parsed_html.at_css('meta[name="description"]')&.[]('content')
  end

  def favicon_url
    return if sitemap?

    href = parsed_html.at_css('link[rel~="icon"]')&.[]('href')
    return if href.blank?

    absolutize(href)
  end

  def page_links
    if sitemap?
      sitemap_document.remove_namespaces!.css('loc').map(&:text)
    else
      parsed_html.css('a[href]').map { |anchor| absolutize(anchor['href']) }.compact.uniq
    end
  end

  private

  def response
    @response ||= HTTParty.get(@url)
  end

  def sitemap?
    @url.end_with?('.xml')
  end

  def parsed_html
    @parsed_html ||= Nokogiri::HTML(response.body)
  end

  def sitemap_document
    @sitemap_document ||= Nokogiri::XML(response.body)
  end

  def absolutize(href)
    URI.join(@url, href).to_s
  rescue URI::Error
    nil
  end
end
