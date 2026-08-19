class Conversations::PermissionFilterService
  CONVERSATION_PERMISSIONS = %w[conversation_manage conversation_unassigned_manage conversation_participating_manage].freeze

  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account, plan_hint_selective_filter: false)
    @conversations = conversations
    @user = user
    @account = account
    @plan_hint_selective_filter = plan_hint_selective_filter
  end

  def perform
    return conversations if unrestricted_access?
    return custom_role_conversations if custom_role.present?

    accessible_conversations
  end

  private

  # Plain administrators and users whose custom role grants conversation_manage
  # see every conversation. A custom role restricts administrators too.
  def unrestricted_access?
    return true if user_role == 'administrator' && custom_role.blank?

    custom_role.present? && permissions.include?('conversation_manage')
  end

  def accessible_conversations
    conversations.where(*base_access_condition)
  end

  def custom_role_conversations
    clauses = []
    params = { user_id: user.id, account_id: account.id }

    if permissions.include?('conversation_unassigned_manage')
      clauses << "((#{inbox_clause} OR #{team_clause}) AND conversations.assignee_id IS NULL AND conversations.assignee_agent_bot_id IS NULL)"
    end
    clauses << 'conversations.assignee_id = :user_id' << participating_clause if permissions.intersect?(CONVERSATION_PERMISSIONS)
    return conversations.none if clauses.empty?

    conversations.where(clauses.join(' OR '), params)
  end

  def base_access_condition
    [[inbox_clause, team_clause].join(' OR '), { user_id: user.id, account_id: account.id }]
  end

  # `inbox_id + 0` keeps the planner from driving the query through an inbox
  # scan, which it grossly misestimates when a highly selective filter (e.g.
  # labels) is present on large accounts (CW-7787).
  def inbox_clause
    column = @plan_hint_selective_filter ? '(conversations.inbox_id + 0)' : 'conversations.inbox_id'
    "#{column} IN (
      SELECT inbox_members.inbox_id FROM inbox_members
      INNER JOIN inboxes ON inboxes.id = inbox_members.inbox_id
      WHERE inbox_members.user_id = :user_id AND inboxes.account_id = :account_id
    )".squish
  end

  def team_clause
    'conversations.team_id IN (SELECT team_members.team_id FROM team_members WHERE team_members.user_id = :user_id)'
  end

  def participating_clause
    'conversations.id IN (
      SELECT conversation_participants.conversation_id FROM conversation_participants
      WHERE conversation_participants.user_id = :user_id AND conversation_participants.account_id = :account_id
    )'.squish
  end

  def account_user
    @account_user ||= AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end

  def custom_role
    account_user&.custom_role
  end

  def permissions
    Array(custom_role&.permissions).map(&:to_s)
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
