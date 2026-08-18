class SamlUserBuilder
  class AuthenticationFailed < StandardError
    def initialize(message = I18n.t('auth.saml.authentication_failed'))
      super
    end
  end

  def initialize(auth_hash, account_id = nil, **kwargs)
    @auth_hash = auth_hash
    @account_id = account_id || kwargs[:account_id]
  end

  def perform
    @account = Account.find(@account_id)

    user = existing_user
    if user
      ensure_user_belongs_to_account(user)
      convert_user_to_saml(user)
    else
      user = create_user
      return user unless user.persisted?
    end

    link_user_to_account(user)
    user
  end

  private

  def email
    @auth_hash.dig('info', 'email')&.downcase
  end

  def existing_user
    @existing_user ||= User.from_email(email)
  end

  def ensure_user_belongs_to_account(user)
    raise AuthenticationFailed unless user.accounts.include?(@account)
  end

  def convert_user_to_saml(user)
    attributes = {}
    attributes[:provider] = 'saml' unless user.provider == 'saml'
    attributes[:confirmed_at] = Time.zone.now if user.confirmed_at.blank?
    user.update_columns(attributes) if attributes.present? # rubocop:disable Rails/SkipsModelValidations
  end

  def create_user
    User.create(
      name: user_name,
      display_name: @auth_hash.dig('info', 'first_name'),
      email: email,
      # suffix keeps the generated password compliant with the secure_password validator
      password: "#{SecureRandom.hex(16)}aA1!",
      confirmed_at: Time.zone.now,
      provider: 'saml'
    )
  end

  def user_name
    @auth_hash.dig('info', 'name').presence || email.split('@').first
  end

  def link_user_to_account(user)
    return if AccountUser.exists?(account_id: @account.id, user_id: user.id)

    AccountUser.create!(
      account_id: @account.id,
      user_id: user.id,
      role: mapped_role,
      custom_role_id: mapped_custom_role_id
    )
  end

  def saml_groups
    @auth_hash.dig('extra', 'raw_info', 'groups') ||
      @auth_hash.dig('extra', 'raw_info', 'memberOf') ||
      []
  end

  def role_mappings
    @role_mappings ||= @account.account_saml_settings&.role_mappings || {}
  end

  def mapped_role
    saml_groups.each do |group|
      role = role_mappings.dig(group, 'role')
      return role if role.present?
    end
    :agent
  end

  def mapped_custom_role_id
    return unless @account.feature_enabled?('custom_roles')

    saml_groups.each do |group|
      custom_role_id = role_mappings.dig(group, 'custom_role_id')
      return custom_role_id if custom_role_id.present?
    end
    nil
  end
end
