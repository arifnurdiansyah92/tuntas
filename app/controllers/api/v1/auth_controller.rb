class Api::V1::AuthController < Api::BaseController
  skip_before_action :authenticate_user!, only: [:saml_login], raise: false

  def saml_login
    return head :bad_request if params[:email].blank?

    account = saml_account_for_email(params[:email])
    if account
      redirect_to saml_initiation_url(account), allow_other_host: true
    else
      redirect_to saml_failure_url, allow_other_host: true
    end
  end

  private

  def saml_account_for_email(email)
    user = User.from_email(email)
    return if user.blank?

    user.accounts.detect do |account|
      account.feature_enabled?('saml') && account.account_saml_settings&.saml_enabled?
    end
  end

  def frontend_url
    ENV.fetch('FRONTEND_URL', nil)
  end

  def saml_initiation_url(account)
    url = "#{frontend_url}/auth/saml?account_id=#{account.id}"
    url += '&RelayState=mobile' if mobile_target?
    url
  end

  def saml_failure_url
    return 'tuntasapp://auth/saml?error=saml-authentication-failed' if mobile_target?

    "#{frontend_url}/app/login/sso?error=saml-authentication-failed"
  end

  def mobile_target?
    params[:target] == 'mobile'
  end
end
