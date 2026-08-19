# Liquid file system that resolves {% render 'snippet' %} tags from the prompt snippets directory
class Captain::SnippetFileSystem
  def read_template_file(template_path)
    path = Captain::PromptRenderer::SNIPPETS_DIR.join("#{template_path}.liquid").to_s
    raise Liquid::FileSystemError, "No such template '#{template_path}'" unless File.exist?(path)

    File.read(path)
  end
end
