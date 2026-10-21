class RecurringRule < ApplicationRecord
  include DollarField

  KINDS = %w[expense income transfer settle].freeze
  FREQUENCIES = %w[once weekly fortnightly monthly yearly].freeze

  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :to_account, class_name: "Account", optional: true
  has_many :transactions, dependent: :nullify

  validates :payee, :frequency, :start_on, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :every, numericality: { only_integer: true, greater_than: 0 }
  validates :amount_cents, presence: true, numericality: { other_than: 0 }, unless: :settle?
  validates :installments, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :to_account, presence: true, if: -> { kind == "transfer" || kind == "settle" }
  validate :transfer_accounts_differ, if: -> { kind == "transfer" || kind == "settle" }
  validate :to_account_only_for_transfers

  before_validation { self.amount_cents = 0 if settle? && amount_cents.nil? }

  belongs_to :scenario, optional: true

  scope :active, -> { where(active: true) }
  scope :live, -> { where(scenario_id: nil) }
  scope :ordered, -> { order(:payee) }

  dollar_field :amount

  def settle? = kind == "settle"

  def signed_amount_cents
    kind == "expense" ? -amount_cents.abs : amount_cents.abs
  end

  # Amount normalized to a monthly rate (cents). Once-rules and settles
  # have no monthly rate — settles estimate from matched actuals.
  def monthly_cents
    case frequency
    when "weekly"      then amount_cents * 52.0 / 12
    when "fortnightly" then amount_cents * 26.0 / 12
    when "monthly"     then amount_cents / every
    when "yearly"      then amount_cents / 12.0
    else 0
    end
  end

  # Matches a real transaction: same account, rule's ref-stripped payee
  # key inside the txn's (bank text carries per-txn refs), and same
  # amount — except settle rules, whose payment varies by cycle.
  def self.match_for(account:, payee:, amount_cents:)
    key = PayeeRule.detection_key(payee)
    return nil if key.blank?
    live.active.where(account: account).select do |r|
      rkey = PayeeRule.detection_key(r.payee)
      rkey.present? && key.include?(rkey) &&
        (r.settle? || r.amount_cents.abs == amount_cents.abs)
    end.max_by { |r| r.payee.length }
  end

  def human_schedule
    if frequency == "once"
      return "once — by #{end_on.strftime("%-d %b %y")}" if end_on
      "once — around #{start_on.strftime("%-d %b %y")}"
    end
    count = every > 1 ? "every #{every} " : "every "
    case frequency
    when "weekly" then "#{count}week#{"s" if every > 1}, #{start_on.strftime("%A")}s"
    when "fortnightly" then "#{count}fortnight#{"s" if every > 1}, #{start_on.strftime("%A")}s"
    when "monthly" then "#{count}month#{"s" if every > 1}, the #{start_on.day.ordinalize}"
    when "yearly" then "yearly, #{start_on.strftime("%-d %b")}"
    end
  end

  private

  def transfer_accounts_differ
    errors.add(:to_account, "can't be the same account") if to_account_id == account_id
  end

  def to_account_only_for_transfers
    if to_account_id.present? && kind != "transfer" && kind != "settle"
      errors.add(:kind, "must be Transfer or Balance payment when a To account is set")
    end
  end
end
