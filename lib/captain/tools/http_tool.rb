class Captain::Tools::HttpTool < Captain::Tools::BasePublicTool
  GENERIC_ERROR_MESSAGE = 'An error occurred while executing the request'.freeze

  attr_reader :custom_tool

  def initialize(assistant, custom_tool)
    super(assistant)
    @custom_tool = custom_tool
  end

  def name
    custom_tool.slug
  end

  def description
    custom_tool.description.presence || super
  end

  def active?
    custom_tool.enabled?
  end

  def perform(tool_context, **params)
    url = custom_tool.build_request_url(params)
    headers = custom_tool.build_auth_headers.merge(custom_tool.build_metadata_headers(tool_context.state || {}))
    body = custom_tool.build_request_body(params)

    response_body = execute_request(url, headers, body)
    custom_tool.format_response(response_body)
  rescue StandardError => e
    Rails.logger.error("HttpTool execution error for #{custom_tool.slug}: #{e.message}")
    GENERIC_ERROR_MESSAGE
  end

  private

  def execute_request(url, headers, body)
    response = perform_http_request(url, headers, body)
    if response.code.between?(300, 399) && response.headers['Location'].present?
      redirect_url = response.headers['Location']
      headers = strip_sensitive_headers(headers, url, redirect_url)
      response = perform_http_request(redirect_url, headers, body)
    end
    raise "HTTP request failed with status #{response.code}" unless response.code.between?(200, 299)

    response.body
  end

  def perform_http_request(url, headers, body)
    options = { headers: headers, follow_redirects: false }
    options[:basic_auth] = basic_auth_option if basic_auth_option
    if custom_tool.http_method == 'POST'
      options[:body] = body
      options[:headers] = options[:headers].merge('Content-Type' => 'application/json')
      HTTParty.post(url, options)
    else
      HTTParty.get(url, options)
    end
  end

  def basic_auth_option
    credentials = custom_tool.build_basic_auth_credentials
    return if credentials.blank?

    { username: credentials[0], password: credentials[1] }
  end

  def strip_sensitive_headers(headers, original_url, redirect_url)
    return headers if same_origin?(original_url, redirect_url)

    headers.except('Authorization', custom_tool.api_key_header_name).compact
  end

  def same_origin?(original_url, redirect_url)
    original = URI.parse(original_url)
    redirect = URI.parse(redirect_url)
    original.scheme == redirect.scheme && original.host == redirect.host && original.port == redirect.port
  rescue URI::InvalidURIError
    false
  end
end
