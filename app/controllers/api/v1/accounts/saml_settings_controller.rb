class Api::V1::Accounts::SamlSettingsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :check_saml_feature_enabled

  def show
    settings = Current.account.account_saml_settings || Current.account.build_account_saml_settings
    render json: settings
  end

  def create
    settings = Current.account.create_account_saml_settings!(saml_settings_params)
    render json: settings
  end

  def update
    settings = Current.account.account_saml_settings
    settings.update!(saml_settings_params)
    render json: settings
  end

  def destroy
    Current.account.account_saml_settings&.destroy!
    head :no_content
  end

  private

  def check_saml_feature_enabled
    return if Current.account.feature_enabled?('saml')

    render json: { error: I18n.t('errors.saml.feature_not_enabled') }, status: :forbidden
  end

  def saml_settings_params
    permitted = params.require(:saml_settings).permit(:sso_url, :certificate, :idp_entity_id, :sp_entity_id)
    role_mappings = params[:saml_settings][:role_mappings]
    permitted[:role_mappings] = role_mappings.permit!.to_h if role_mappings.present?
    permitted
  end
end
