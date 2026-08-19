class Captain::Assistant::ResponseParts
  MESSAGE_ATTRIBUTE_KEY = 'captain_response_parts'.freeze
  CODE_FENCE_ENDING = /```\s*\z/

  attr_reader :parts

  def self.from_response(output)
    new(extract_parts(output))
  end

  def self.extract_parts(output)
    if output.is_a?(Hash)
      raw_parts = output['response_parts']
      return sanitize(raw_parts) if raw_parts.is_a?(Array)

      return wrap_text(output['response'])
    end

    wrap_text(output)
  end

  def self.wrap_text(text)
    return [] if text.blank?

    [{ 'text' => text.to_s, 'citation_indexes' => [] }]
  end

  def self.sanitize(raw_parts)
    raw_parts.filter_map do |part|
      next unless part.is_a?(Hash)

      text = part['text'].to_s.strip
      next if text.blank?

      { 'text' => text, 'citation_indexes' => sanitize_indexes(part['citation_indexes']) }
    end
  end

  def self.sanitize_indexes(indexes)
    Array(indexes).select { |index| index.is_a?(Integer) && index.positive? }.uniq
  end

  def initialize(parts)
    @parts = parts
  end

  def blank?
    parts.blank?
  end

  def plain_text
    parts.pluck('text').join("\n\n")
  end

  def without_citations
    self.class.new(parts.map { |part| part.merge('citation_indexes' => []) })
  end

  def citation_indexes
    parts.flat_map { |part| part['citation_indexes'] }.uniq
  end

  # Renders the customer-facing message, appending citation links numbered by
  # first appearance. Only indexes present in the trusted citation_urls mapping
  # are rendered; everything else the model claimed is dropped.
  def customer_message_content(citation_urls:)
    display_numbers = {}

    parts.map { |part| render_part(part, citation_urls, display_numbers) }.join("\n\n")
  end

  private

  def render_part(part, citation_urls, display_numbers)
    citations = part['citation_indexes'].filter_map do |index|
      url = citation_urls[index]
      next if url.blank?

      display_numbers[index] ||= display_numbers.size + 1
      "[[#{display_numbers[index]}](#{encode_markdown_url(url)})]"
    end

    return part['text'] if citations.blank?

    separator = part['text'].match?(CODE_FENCE_ENDING) ? "\n" : ' '
    "#{part['text']}#{separator}#{citations.join(' ')}"
  end

  def encode_markdown_url(url)
    url.to_s.gsub('(', '%28').gsub(')', '%29').gsub('[', '%5B').gsub(']', '%5D')
  end
end
