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
end
