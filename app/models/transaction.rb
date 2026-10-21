class Transaction < ApplicationRecord
  include DollarField

  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :import, optional: true
  belongs_to :user, optional: true
  belongs_to :recurring_rule, optional: true

  validates :posted_on, presence: true
  validates :amount_cents, presence: true, numericality: { other_than: 0 }

  # Whether saving this txn teaches a payee→category rule — the form
  # checkbox, and skipped on import (the category came FROM a rule).
  attribute :learn_rule, :boolean, default: true

  # Payee → category rules learned whenever a categorised txn has a payee.
  after_save :learn_payee_rule, if: -> { learn_rule && saved_change_to_category_id? && category_id.present? && payee.present? }
  # Link to a matching recurring rule (payee substring + same amount).
  before_validation :suggest_rule, if: -> { recurring_rule_id.nil? && account_id.present? && payee.present? && amount_cents.present? }
  # A linked one-off rule resolves itself — the planned expense occurred.
  after_save :resolve_once_rule, if: -> { saved_change_to_recurring_rule_id? && recurring_rule_id.present? }
  # Own-account movements (savings↔savings, bank→card) pair themselves —
  # same |amount| on another non-loan account within a few days' lag.
  after_create :pair_transfer!

  # Payee text hinting at an own-account move: another account's name,
  # or generic transfer markers.
  TRANSFERISH = /transfer|osko|payment|paid|sav|redraw|settlement/i.freeze

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

  private

  # Pairs this txn with its own-account mirror: equal |amount|,
  # opposite sign, different liquid account, within 5 days.
  # Liquid-only: paying a card or a loan is real outflow, not a shuffle.
  def pair_transfer!
    return if transfer_pair_id.present? || !account&.liquid?
    key = PayeeRule.detection_key(payee)
    names = Account.liquid.where.not(id: account_id).map(&:name)
    return unless key.match?(TRANSFERISH) || names.any? { |n| key.include?(PayeeRule.normalize(n)) }
    cand = Transaction.where(transfer_pair_id: nil, posted_on: (posted_on - 5.days)..(posted_on + 5.days))
                      .where.not(account_id:, id:)
                      .where("SIGN(amount_cents) != SIGN(?) AND ABS(amount_cents) = ?", amount_cents, amount_cents.abs)
                      .joins(:account).merge(Account.liquid)
                      .order(:id).first
    return unless cand
    pair = SecureRandom.uuid
    update_column(:transfer_pair_id, pair)
    cand.update_column(:transfer_pair_id, pair)
  end

  def learn_payee_rule
    PayeeRule.learn(payee, category, amount_cents)
  end

  def suggest_rule
    self.recurring_rule = RecurringRule.match_for(account:, payee:, amount_cents:)
  end

  def resolve_once_rule
    recurring_rule&.update!(active: false) if recurring_rule&.frequency == "once"
  end
end
