class Captain::PromptRenderer
  TEMPLATE_DIR = Rails.root.join('lib/captain/prompts').freeze
  SNIPPETS_DIR = Rails.root.join('lib/captain/prompts/snippets').freeze

  class << self
    def render(template_name, context = {})
      template = Liquid::Template.parse(load_template(template_name))
      template.render(stringify_keys(context), registers: { file_system: Captain::SnippetFileSystem.new })
    end

    private

    def load_template(template_name)
      path = TEMPLATE_DIR.join("#{template_name}.liquid")
      raise "Template not found: #{template_name}" unless File.exist?(path)

      File.read(path)
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, val), result| result[key.to_s] = stringify_keys(val) }
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end
  end
end
