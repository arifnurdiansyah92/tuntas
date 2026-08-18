class Api::V1::Accounts::AuditLogsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  RESULTS_PER_PAGE = 25

  def show
    return render_empty unless Current.account.feature_enabled?('audit_logs')

    @audit_logs = AuditLog.for_account(Current.account.id)
                          .order(created_at: :desc, id: :desc)
                          .page(params[:page])
                          .per(RESULTS_PER_PAGE)

    render json: {
      audit_logs: @audit_logs,
      current_page: @audit_logs.current_page,
      per_page: RESULTS_PER_PAGE,
      total_entries: @audit_logs.total_count
    }
  end

  private

  def render_empty
    render json: { audit_logs: [], current_page: 1, per_page: RESULTS_PER_PAGE, total_entries: 0 }
  end
end
