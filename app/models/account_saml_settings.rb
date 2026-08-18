# == Schema Information
#
# Table name: account_saml_settings
#
#  id            :bigint           not null, primary key
#  certificate   :text
#  idp_entity_id :string
#  role_mappings :json             default({})
#  sp_entity_id  :string
#  sso_url       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
class AccountSamlSettings < ApplicationRecord
  belongs_to :account

  validates :sso_url, presence: true
  validates :certificate, presence: true
  validates :idp_entity_id, presence: true

  before_validation :ensure_sp_entity_id, on: :create
  after_create_commit :enable_saml_provider_for_users
  after_destroy_commit :reset_saml_provider_for_users

  def saml_enabled?
    sso_url.present? && certificate.present?
  end

  def certificate_fingerprint
    return if certificate.blank?

    cert = OpenSSL::X509::Certificate.new(certificate)
    OpenSSL::Digest::SHA1.hexdigest(cert.to_der).upcase.scan(/../).join(':')
  rescue OpenSSL::X509::CertificateError
    nil
  end

  private

  def ensure_sp_entity_id
    self.sp_entity_id = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/saml/sp/#{account_id}" if sp_entity_id.blank?
  end

  def enable_saml_provider_for_users
    Saml::UpdateAccountUsersProviderJob.perform_later(account_id, 'saml')
  end

  def reset_saml_provider_for_users
    Saml::UpdateAccountUsersProviderJob.perform_later(account_id, 'email')
  end
end
