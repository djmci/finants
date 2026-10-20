class RecurringRule < ApplicationRecord
  include DollarField

  KINDS = %w[expense income transfer].freeze
  FREQUENCIES = %w[weekly fortnightly monthly yearly].freeze

  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :to_account, class_name: "Account", optional: true
  has_many :transactions, dependent: :nullify

  validates :payee, :frequency, :start_on, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :every, numericality: { only_integer: true, greater_than: 0 }
  validates :amount_cents, presence: true, numericality: { other_than: 0 }
  validates :to_account, presence: true, if: -> { kind == "transfer" }
  validate :transfer_accounts_differ, if: -> { kind == "transfer" }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:payee) }

  dollar_field :amount

  def signed_amount_cents
    kind == "expense" ? -amount_cents.abs : amount_cents.abs
  end

  # Matches a real transaction: same account, same amount magnitude,
  # rule payee as substring of the txn payee (normalised, like PayeeRule).
  def self.match_for(account:, payee:, amount_cents:)
    norm = PayeeRule.normalize(payee)
    return nil if norm.blank?
    active.where(account: account).select do |r|
      r.amount_cents.abs == amount_cents.abs &&
        norm.include?(PayeeRule.normalize(r.payee))
    end.max_by { |r| r.payee.length }
  end

  def human_schedule
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
end
