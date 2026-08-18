class SuperAdmin::PlatformBannersController < SuperAdmin::ApplicationController
  before_action :ensure_tuntas_cloud

  private

  def ensure_tuntas_cloud
    raise ActionController::RoutingError, 'Not Found' unless TuntasApp.tuntas_cloud?
  end
end
