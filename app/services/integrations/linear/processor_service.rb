class Integrations::Linear::ProcessorService
  API_URL = 'https://api.linear.app/graphql'.freeze

  SEARCH_ISSUE_QUERY = <<~GRAPHQL.freeze
    query SearchIssues($term: String!) {
      searchIssues(term: $term) {
        nodes {
          id
          identifier
          title
          description
          priority
          state { name }
          assignee { name }
        }
      }
    }
  GRAPHQL

  def initialize(account:)
    @account = account
  end

  def search_issue(term)
    response = execute_query(SEARCH_ISSUE_QUERY, term: term.to_s)
    return response if response[:error].present?

    { data: response.dig('data', 'searchIssues', 'nodes') || [] }
  end

  private

  def hook
    @hook ||= @account.hooks.find_by(app_id: 'linear', status: :enabled)
  end

  def execute_query(query, variables)
    return { error: 'Linear integration is not enabled' } if hook.blank?

    response = HTTParty.post(
      API_URL,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => hook.access_token
      },
      body: { query: query, variables: variables }.to_json
    )
    parse_response(response)
  rescue StandardError => e
    { error: e.message }
  end

  def parse_response(response)
    return { error: "Linear API error: #{response.code}" } unless response.success?

    body = response.parsed_response
    errors = body['errors']
    return { error: errors.filter_map { |error| error['message'] }.join(', ') } if errors.present?

    body
  end
end
