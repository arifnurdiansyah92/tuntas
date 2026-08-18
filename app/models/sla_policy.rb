# == Schema Information
#
# Table name: sla_policies
#
#  id                            :bigint           not null, primary key
#  description                   :string
#  first_response_time_threshold :float
#  name                          :string           not null
#  next_response_time_threshold  :float
#  only_during_business_hours    :boolean          default(FALSE)
#  resolution_time_threshold     :float
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#
# Indexes
#
#  index_sla_policies_on_account_id  (account_id)
#
class SlaPolicy < ApplicationRecord
  belongs_to :account
  has_many :conversations, dependent: :nullify
  has_many :applied_slas, dependent: :destroy_async
  has_many :sla_events, dependent: :destroy_async

  validates :name, presence: true
end
