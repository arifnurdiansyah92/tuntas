# == Schema Information
#
# Table name: captain_faq_suggestions
#
#  id           :bigint           not null, primary key
#  answer       :text             not null
#  embedding    :vector(1536)
#  language     :string           default("en"), not null
#  question     :string           not null
#  source_count :integer          default(0), not null
#  status       :integer          default("open"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  assistant_id :bigint           not null
#
class Captain::FaqSuggestion < ApplicationRecord
  self.table_name = 'captain_faq_suggestions'

  has_neighbors :embedding

  belongs_to :assistant, class_name: 'Captain::Assistant', inverse_of: :faq_suggestions
  belongs_to :account
  has_many :observations, class_name: 'Captain::FaqObservation',
                          dependent: :nullify, inverse_of: :faq_suggestion

  enum :status, { open: 0, approved: 1, dismissed: 2 }

  validates :question, presence: true
  validates :answer, presence: true

  before_validation :ensure_account

  private

  def ensure_account
    self.account ||= assistant&.account
  end
end
