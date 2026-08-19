class Captain::Tools::BaseService
  attr_reader :assistant, :user

  def initialize(assistant, user: nil)
    @assistant = assistant
    @user = user
  end

  def name
    raise NotImplementedError
  end

  def description
    raise NotImplementedError
  end

  def parameters
    {}
  end

  def execute(*_args)
    raise NotImplementedError
  end

  def active?
    true
  end

  private

  def account
    assistant.account
  end

  # A user holds a permission when they are a plain administrator/agent (full
  # default permissions) or their custom role explicitly grants it. A custom
  # role restricts administrators too.
  def user_has_permission?(*permissions)
    return false if user.blank?

    account_user = account.account_users.find_by(user_id: user.id)
    return false if account_user.blank?
    return true if account_user.custom_role.blank?

    Array(account_user.custom_role.permissions).intersect?(permissions.map(&:to_s))
  end
end
