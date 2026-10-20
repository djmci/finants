class Transaction < ApplicationRecord
  include DollarField

  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :import, optional: true
  belongs_to :user, optional: true

  validates :posted_on, presence: true
  validates :amount_cents, presence: true, numericality: { other_than: 0 }

  scope :ordered, -> { order(posted_on: :desc, id: :desc) }
  scope :uncategorised, -> { where(category_id: nil) }
  scope :excluding_transfers, -> { where(transfer_pair_id: nil) }
  scope :income, -> { where("amount_cents > 0") }
  scope :expenses, -> { where("amount_cents < 0") }
  scope :for_owner, ->(owner) {
    owner.to_s == "joint" ? joins(:account).where(accounts: { owner_id: nil })
                        : joins(:account).where(accounts: { owner_id: owner })
  }

  dollar_field :amount

  def direction
    amount_cents.to_i < 0 ? "expense" : "income"
  end

  def transfer?
    transfer_pair_id.present?
  end

  def transfer_pair
    return unless transfer?
    Transaction.where(transfer_pair_id:).where.not(id:).first
  end

  def self.create_transfer!(from_account:, to_account:, posted_on:, amount:, notes: nil, user: nil)
    pair = SecureRandom.uuid
    cents = (BigDecimal(amount.to_s) * 100).round.abs
    txns = nil
    transaction do
      txns = [
        create!(account: from_account, posted_on:, amount_cents: -cents, payee: to_account.name, notes:, user:, transfer_pair_id: pair),
        create!(account: to_account, posted_on:, amount_cents: cents, payee: from_account.name, notes:, user:, transfer_pair_id: pair)
      ]
    end
    txns
  end
end
