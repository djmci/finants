class Import < ApplicationRecord
  belongs_to :user
  belongs_to :account, optional: true
  has_many :transactions, dependent: :destroy
end
