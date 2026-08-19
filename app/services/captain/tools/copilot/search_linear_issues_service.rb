class Captain::Tools::Copilot::SearchLinearIssuesService < Captain::Tools::BaseService
  PRIORITY_LABELS = {
    0 => 'No priority',
    1 => 'Urgent',
    2 => 'High',
    3 => 'Medium',
    4 => 'Low'
  }.freeze

  def name
    'search_linear_issues'
  end

  def description
    'Search Linear issues based on a search term'
  end

  def parameters
    {
      term: {
        type: 'string',
        description: 'The search term to look up Linear issues'
      }
    }
  end

  def execute(term: nil)
    return 'Linear integration is not enabled' unless linear_enabled?

    result = Integrations::Linear::ProcessorService.new(account: account).search_issue(term.to_s)
    return result[:error] if result[:error].present?

    issues = Array(result[:data])
    return 'No issues found, I should try another similar search term' if issues.blank?

    format_issues(issues)
  end

  def active?
    linear_enabled? && user.present?
  end

  private

  def linear_enabled?
    account.hooks.exists?(app_id: 'linear', status: :enabled)
  end

  def format_issues(issues)
    sections = ["Total number of issues: #{issues.size}"]
    sections += issues.map { |issue| format_issue(issue) }
    sections.join("\n\n")
  end

  def format_issue(issue)
    [
      "Title: #{issue['title']}",
      "ID: #{issue['id']}",
      "State: #{issue.dig('state', 'name')}",
      "Priority: #{PRIORITY_LABELS[issue['priority']]}",
      "Assignee: #{issue.dig('assignee', 'name')}",
      "Description: #{issue['description']}"
    ].join("\n")
  end
end
