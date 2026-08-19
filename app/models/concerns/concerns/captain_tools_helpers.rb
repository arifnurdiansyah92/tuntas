module Concerns::CaptainToolsHelpers
  extend ActiveSupport::Concern

  # Matches markdown-style tool references: [Label](tool://tool_id)
  TOOL_REFERENCE_REGEX = %r{\[[^\]]+\]\(tool://([a-z0-9_-]+)\)}

  class_methods do
    def resolve_tool_class(tool_id)
      "Captain::Tools::#{tool_id.camelize}Tool".safe_constantize
    end
  end

  def extract_tool_ids_from_text(text)
    return [] if text.blank?

    text.scan(TOOL_REFERENCE_REGEX).flatten.uniq
  end
end
