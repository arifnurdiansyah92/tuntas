class Captain::AssistantPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def playground?
    true
  end

  def metrics?
    true
  end

  def faq_stats?
    true
  end

  def tools?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def sync?
    @account_user.administrator?
  end

  def drilldown?
    @account_user.administrator?
  end
end
