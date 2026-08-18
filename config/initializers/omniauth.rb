# OmniAuth configuration
# Sets the full host URL for callbacks and proper redirect handling
OmniAuth.config.full_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

# SAML SP-initiated SSO enters via a browser redirect (GET); POST-only would 404 the request phase
OmniAuth.config.allowed_request_methods = %i[post get]
OmniAuth.config.silence_get_warning = true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }

  # SAML settings are resolved per account at request time via the setup phase.
  # The account_id rides the query string on both phases (the ACS URL embeds it for
  # the IdP callback) and is stashed in the session for the post-callback hop.
  provider :saml, setup: lambda { |env|
    request = Rack::Request.new(env)
    account_id = request.params['account_id']
    settings = account_id.present? ? AccountSamlSettings.find_by(account_id: account_id) : nil

    if settings&.saml_enabled?
      base_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
      env['omniauth.strategy'].options.merge!(
        sp_entity_id: settings.sp_entity_id,
        idp_sso_service_url: settings.sso_url,
        idp_cert: settings.certificate,
        idp_entity_id: settings.idp_entity_id,
        assertion_consumer_service_url: "#{base_url}/omniauth/saml/callback?account_id=#{settings.account_id}"
      )
      env['rack.session']['saml.account_id'] = settings.account_id
      env['rack.session']['saml.relay_mobile'] = true if request.params['RelayState'] == 'mobile'
    end
  }
end
