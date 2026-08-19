class Captain::ToolRegistryService
  attr_reader :tools, :registered_tools

  def initialize(assistant, user: nil)
    @assistant = assistant
    @user = user
    @tools = {}
    @registered_tools = []
  end

  def register_tool(tool_class)
    tool = tool_class.new(@assistant, user: @user)
    return unless tool.active?

    @tools[tool.name] = tool
    @registered_tools << {
      type: 'function',
      function: {
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters
      }
    }
  end

  def tools_summary
    @tools.values.map { |tool| "- #{tool.name}: #{tool.description}" }.join("\n")
  end

  def method_missing(method_name, *, **)
    tool = @tools[method_name.to_s]
    return super if tool.blank?

    tool.execute(*, **)
  end

  def respond_to_missing?(method_name, include_private = false)
    @tools.key?(method_name.to_s) || super
  end
end
