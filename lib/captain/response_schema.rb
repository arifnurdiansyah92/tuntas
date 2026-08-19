class Captain::ResponseSchema < RubyLLM::Schema
  array :response_parts, min_items: 1 do
    object do
      string :text
      array :citation_indexes, required: false do
        integer minimum: 1
      end
    end
  end
  string :reasoning
end
