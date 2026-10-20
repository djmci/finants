class Account < ApplicationRecord
  include DollarField

  KINDS = %w[everyday savings credit cash loan].freeze

  dollar_field :opening_balance

  belongs_to :owner, class_name: "User", optional: true
  has_many :transactions, dependent: :destroy
  has_many :imports, dependent: :destroy

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(active: true) }
  scope :joint, -> { where(owner_id: nil) }

  def balance_cents(on: nil)
    scope = transactions
    scope = scope.where(posted_on: ..on) if on
    opening_balance_cents + scope.sum(:amount_cents)
  end

  # {txn_id => balance in cents after that txn}, across all transactions.
  def running_balances
    balance = opening_balance_cents
    transactions.order(:posted_on, :id).pluck(:id, :amount_cents).map do |id, cents|
      [ id, balance += cents ]
    end.to_h
  end

  def owner_label
    owner&.name || "Joint"
  end
end
