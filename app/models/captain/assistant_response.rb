# == Schema Information
#
# Table name: captain_assistant_responses
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  edited            :boolean          default(FALSE), not null
#  embedding         :vector(1536)
#  question          :string           not null
#  status            :integer          default("approved"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint           not null
#  documentable_id   :bigint
#  documentable_type :string
#
class Captain::AssistantResponse < ApplicationRecord
  self.table_name = 'captain_assistant_responses'

  has_neighbors :embedding

  belongs_to :assistant, class_name: 'Captain::Assistant', inverse_of: :responses
  belongs_to :account
  belongs_to :documentable, polymorphic: true, optional: true

  enum :status, { pending: 0, approved: 1 }

  validates :question, presence: true
  validates :answer, presence: true
  validate :validate_assistant_account

  before_validation :ensure_account

  private

  def ensure_account
    self.account ||= assistant&.account
  end

  def validate_assistant_account
    return if assistant.blank? || account.blank?
    return if assistant.account_id == account_id

    errors.add(:assistant, 'is invalid')
  end
end
