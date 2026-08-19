# Structured output for the coverage audit pass. Only categories with remaining
# capacity are representable, each capped at the capacity the draft has left.
class Captain::AssistantMigration::InstructionAuditorSchema
  STRING_CATEGORIES = %i[response_guidelines guardrails needs_review].freeze
  OBJECT_CATEGORY_FIELDS = {
    scenario_candidates: %i[title description instruction response_guideline],
    faq_document_candidates: %i[question answer]
  }.freeze

  def self.for(**capacities)
    string_categories = STRING_CATEGORIES
    object_category_fields = OBJECT_CATEGORY_FIELDS

    Class.new(RubyLLM::Schema) do
      capacities.each do |category, capacity|
        next if capacity.to_i <= 0

        if string_categories.include?(category)
          array category, max_items: capacity.to_i do
            string
          end
        elsif object_category_fields.key?(category)
          fields = object_category_fields[category]
          array category, max_items: capacity.to_i do
            object do
              fields.each { |field| string field }
            end
          end
        end
      end
    end
  end
end
