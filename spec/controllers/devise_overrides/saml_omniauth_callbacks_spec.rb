require 'rails_helper'

RSpec.describe 'SAML Omniauth Callbacks', type: :request do
  let(:account) { create(:account) }
  let(:saml_settings) { create(:account_saml_settings, account: account) }
  let(:email) { 'saml.user@example.com' }

  def set_saml_omniauth_config(for_email)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(
      provider: 'saml',
      uid: 'saml-uid-1',
      info: { name: 'Saml User', email: for_email },
      extra: { raw_info: { 'groups' => [] } }
    )
  end

  def follow_saml_redirects!
    5.times do
      break unless response.redirect? &&
                   response.location.start_with?('http') &&
                   response.location.match?(%r{/(omniauth|auth)/saml(/callback)?(\?|\z)})

      follow_redirect!
    end
  end

  before do
    account.enable_features!('saml')
    saml_settings
    set_saml_omniauth_config(email)
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:saml] = nil
  end

  describe 'successful web login' do
    it 'provisions the user and redirects to login with an SSO token' do
      with_modified_env FRONTEND_URL: 'http://www.example.com' do
        get "/auth/saml?account_id=#{account.id}"
        follow_saml_redirects!

        expect(response.location).to match(%r{http://www\.example\.com/app/login\?email=.*&sso_auth_token=.+})

        user = User.from_email(email)
        expect(user).to be_present
        expect(user.provider).to eq('saml')
        expect(user.accounts).to include(account)
      end
    end
  end

  describe 'successful mobile login' do
    it 'redirects to the mobile deep link with an SSO token' do
      with_modified_env FRONTEND_URL: 'http://www.example.com' do
        get "/auth/saml?account_id=#{account.id}&RelayState=mobile"
        follow_saml_redirects!

        expect(response.location).to match(%r{\Atuntasapp://auth/saml\?email=.*&sso_auth_token=.+})
      end
    end
  end

  describe 'failed login' do
    context 'when the user belongs to a different account' do
      let(:other_account) { create(:account) }

      before { create(:user, email: email, account: other_account) }

      it 'redirects to the SSO login page with an error' do
        with_modified_env FRONTEND_URL: 'http://www.example.com' do
          get "/auth/saml?account_id=#{account.id}"
          follow_saml_redirects!

          expect(response.location).to eq('http://www.example.com/app/login/sso?error=saml-authentication-failed')
        end
      end

      it 'redirects to the mobile deep link with an error when RelayState is mobile' do
        with_modified_env FRONTEND_URL: 'http://www.example.com' do
          get "/auth/saml?account_id=#{account.id}&RelayState=mobile"
          follow_saml_redirects!

          expect(response.location).to eq('tuntasapp://auth/saml?error=saml-authentication-failed')
        end
      end
    end

    context 'when the account id is missing' do
      it 'redirects to the SSO login page with an error' do
        with_modified_env FRONTEND_URL: 'http://www.example.com' do
          get '/omniauth/saml/callback'
          follow_saml_redirects!

          expect(response.location).to eq('http://www.example.com/app/login/sso?error=saml-authentication-failed')
        end
      end
    end
  end
end
