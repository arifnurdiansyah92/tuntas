# Structured output for the V1 -> V2 instruction classification pass.
class Captain::AssistantMigration::InstructionClassifierSchema < RubyLLM::Schema
  array :business_product_context do
    string
  end
  array :response_guidelines do
    string
  end
  array :guardrails do
    string
  end
  array :scenario_candidates do
    object do
      string :title
      string :description
      string :instruction
      string :response_guideline
      array :tool_ids, required: false do
        string
      end
    end
  end
  array :faq_document_candidates do
    object do
      string :question
      string :answer
    end
  end
  array :needs_review do
    string
  end
end
