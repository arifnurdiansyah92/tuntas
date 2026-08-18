class Saml::UpdateAccountUsersProviderJob < ApplicationJob
  queue_as :low

  def perform(account_id, provider)
    account = Account.find(account_id)

    account.users.find_each do |user|
      next if provider == 'email' && saml_enabled_on_other_account?(user, account)

      user.update_column(:provider, provider) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def saml_enabled_on_other_account?(user, account)
    AccountSamlSettings.exists?(account_id: user.account_ids - [account.id])
  end
end
