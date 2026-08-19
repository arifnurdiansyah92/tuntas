module Captain::Toolable
  extend ActiveSupport::Concern

  def build_request_url(params)
    Liquid::Template.parse(endpoint_url).render(stringify_params(params))
  end

  def build_request_body(params)
    return if request_template.blank?

    Liquid::Template.parse(request_template).render(stringify_params(params))
  end

  def build_auth_headers
    case auth_type
    when 'bearer'
      { 'Authorization' => "Bearer #{auth_config['token']}" }
    when 'api_key'
      { api_key_header_name => auth_config['key'] }
    else
      {}
    end
  end

  def api_key_header_name
    auth_config['name'] || 'X-API-Key'
  end

  def build_basic_auth_credentials
    return unless auth_basic?

    [auth_config['username'], auth_config['password']]
  end

  def format_response(raw_response)
    return raw_response if response_template.blank?

    parsed = begin
      JSON.parse(raw_response)
    rescue JSON::ParserError, TypeError
      raw_response
    end
    Liquid::Template.parse(response_template).render('response' => parsed)
  end

  def build_metadata_headers(state)
    {
      'X-Tuntas-Account-Id' => state[:account_id]&.to_s,
      'X-Tuntas-Assistant-Id' => state[:assistant_id]&.to_s,
      'X-Tuntas-Tool-Slug' => slug,
      'X-Tuntas-Conversation-Id' => state.dig(:conversation, :id)&.to_s,
      'X-Tuntas-Conversation-Display-Id' => state.dig(:conversation, :display_id)&.to_s,
      'X-Tuntas-Contact-Inbox-Id' => state.dig(:contact_inbox, :id)&.to_s,
      'X-Tuntas-Contact-Inbox-Verified' => contact_inbox_verified_header(state),
      'X-Tuntas-Contact-Id' => state.dig(:contact, :id)&.to_s,
      'X-Tuntas-Contact-Email' => state.dig(:contact, :email).presence,
      'X-Tuntas-Contact-Phone' => state.dig(:contact, :phone_number).presence
    }.compact
  end

  def contact_inbox_verified_header(state)
    state.dig(:contact_inbox, :hmac_verified) ? 'true' : 'false'
  end

  def to_tool_metadata
    { id: slug, title: title, description: description, custom: true }
  end

  def tool(assistant)
    tool_class = Class.new(Captain::Tools::HttpTool)
    tool_class.description(description)
    param_schema.each do |param|
      tool_class.param(
        param['name'].to_sym,
        type: param['type'],
        desc: param['description'],
        required: param.fetch('required', false)
      )
    end
    tool_class.new(assistant, self)
  end

  private

  def stringify_params(params)
    params.transform_keys(&:to_s).transform_values { |value| value.is_a?(Hash) ? value.transform_keys(&:to_s) : value }
  end
end
