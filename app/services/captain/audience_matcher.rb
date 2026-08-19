class Captain::AudienceMatcher
  STANDARD_ATTRIBUTES = %w[email phone_number identifier name blocked created_at contact_type].freeze

  def initialize(audience)
    @audience = audience.presence&.deep_stringify_keys
  end

  def matches?(contact, conversation)
    return true if @audience.blank?

    evaluate_node(@audience, contact, conversation)
  end

  private

  def evaluate_node(node, contact, conversation)
    if node['conditions'].present?
      results = Array(node['conditions']).map { |child| evaluate_node(child.deep_stringify_keys, contact, conversation) }
      node['operator'] == 'or' ? results.any? : results.all?
    else
      evaluate_leaf(node, contact, conversation)
    end
  end

  def evaluate_leaf(leaf, contact, conversation)
    attribute = resolve_attribute(leaf['attribute_key'].to_s, contact, conversation)
    values = Array(leaf['values']).flatten.map(&:to_s)

    apply_operator(leaf['filter_operator'].to_s, attribute, values)
  end

  # Resolves the leaf into { value:, custom:, labels:, phone: } so operators can
  # apply the null semantics of the attribute class the UI filter came from.
  def resolve_attribute(key, contact, conversation)
    resolve_conversation_attribute(key, conversation) ||
      resolve_contact_attribute(key, contact) ||
      resolve_custom_attribute(key, contact)
  end

  def resolve_conversation_attribute(key, conversation)
    case key
    when 'browser_language' then { value: conversation&.additional_attributes&.[]('browser_language') }
    when 'hmac_verified' then { value: conversation&.contact_inbox&.hmac_verified || false }
    end
  end

  def resolve_contact_attribute(key, contact)
    return { value: contact.label_list.map(&:to_s), labels: true } if key == 'labels'
    return { value: contact.public_send(key), phone: key == 'phone_number' } if STANDARD_ATTRIBUTES.include?(key)

    additional = contact.additional_attributes || {}
    { value: additional[key] } if additional.key?(key)
  end

  def resolve_custom_attribute(key, contact)
    custom = contact.custom_attributes || {}
    definition = custom_attribute_definition(key, contact)
    return { value: custom[key], custom: true } if custom.key?(key)
    return { value: false, custom: true } if definition&.attribute_display_type == 'checkbox'
    return { value: nil, custom: true } if definition.present?

    { value: nil }
  end

  def custom_attribute_definition(key, contact)
    contact.account.custom_attribute_definitions.find_by(attribute_model: 'contact_attribute', attribute_key: key)
  end

  OPERATOR_METHODS = {
    'equal_to' => :equal_to?,
    'not_equal_to' => :not_equal_to?,
    'contains' => :contains?,
    'does_not_contain' => :negated_contains?,
    'starts_with' => :starts_with?,
    'is_present' => :present_attribute?,
    'is_not_present' => :absent_attribute?,
    'days_before' => :days_before?,
    'is_greater_than' => :greater_than?,
    'is_less_than' => :less_than?
  }.freeze

  def apply_operator(operator, attribute, values)
    method_name = OPERATOR_METHODS[operator]
    return false if method_name.blank?

    send(method_name, attribute, values)
  end

  def present_attribute?(attribute, _values)
    attribute[:value].present? || attribute[:value] == false
  end

  def absent_attribute?(attribute, _values)
    attribute[:value].blank? && attribute[:value] != false
  end

  def greater_than?(attribute, values)
    compare_values(attribute, values) { |value, candidate| value > candidate }
  end

  def less_than?(attribute, values)
    compare_values(attribute, values) { |value, candidate| value < candidate }
  end

  def equal_to?(attribute, values)
    return attribute[:value].intersect?(values) if attribute[:labels]

    present_value(attribute) { |value| values.any? { |candidate| value_equals?(value, candidate, attribute) } }
  end

  def not_equal_to?(attribute, values)
    return !attribute[:value].intersect?(values) if attribute[:labels]
    return attribute[:custom] == true if missing?(attribute)

    !equal_to?(attribute, values)
  end

  def contains?(attribute, values)
    present_value(attribute) { |value| values.any? { |candidate| value.to_s.downcase.include?(candidate.downcase) } }
  end

  def negated_contains?(attribute, values)
    return false if missing?(attribute)

    !contains?(attribute, values)
  end

  def starts_with?(attribute, values)
    present_value(attribute) { |value| values.any? { |candidate| value.to_s.downcase.start_with?(candidate.downcase) } }
  end

  def days_before?(attribute, values)
    present_value(attribute) do |value|
      threshold = values.first.to_f
      value.to_time < threshold.days.ago
    end
  end

  def compare_values(attribute, values)
    present_value(attribute) do |value|
      candidate = values.first
      left, right = comparable_pair(value, candidate)
      left.present? && right.present? && yield(left, right)
    end
  end

  def comparable_pair(value, candidate)
    date_left = safe_date(value)
    date_right = safe_date(candidate)
    return [date_left, date_right] if date_left && date_right

    [numeric(value), numeric(candidate)]
  end

  def value_equals?(value, candidate, attribute)
    return normalize_phone(value) == normalize_phone(candidate) if attribute[:phone]

    left = numeric(value)
    right = numeric(candidate)
    return left == right if left && right

    value.to_s.casecmp?(candidate)
  end

  def present_value(attribute)
    return false if missing?(attribute)

    yield(attribute[:value])
  end

  def missing?(attribute)
    attribute[:value].nil? || (attribute[:value].respond_to?(:empty?) && attribute[:value].empty? && !attribute[:labels])
  end

  def normalize_phone(value)
    value.to_s.delete('+')
  end

  def numeric(value)
    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def safe_date(value)
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
