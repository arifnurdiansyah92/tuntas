# == Schema Information
#
# Table name: custom_roles
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string
#  permissions :text             default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
class CustomRole < ApplicationRecord
  include Events::Types

  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_manage
    report_manage
    knowledge_base_manage
  ].freeze

  belongs_to :account
  has_many :account_users, dependent: :nullify

  validates :name, presence: true

  after_update :invalidate_assigned_users_visibility, if: :saved_change_to_permissions?
  before_destroy :capture_assigned_user_ids, prepend: true
  after_destroy :invalidate_assigned_users_visibility

  private

  # captured before dependent: :nullify clears the association
  def capture_assigned_user_ids
    @assigned_user_ids = account_users.pluck(:user_id)
  end

  def invalidate_assigned_users_visibility
    user_ids = @assigned_user_ids || account_users.pluck(:user_id)
    return if user_ids.blank?

    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).users_visibility_changed!(user_ids: user_ids)
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end
