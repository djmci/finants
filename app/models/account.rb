class Account < ApplicationRecord
  include DollarField

  KINDS = %w[everyday savings credit cash loan].freeze
  LIQUID = %w[everyday savings cash].freeze

  dollar_field :opening_balance

  belongs_to :owner, class_name: "User", optional: true
  # The accounts this one replaces (e.g. after a refinance): the old
  # accounts keep the history, this one carries the projection.
  has_many :account_predecessors, dependent: :destroy
  has_many :predecessors, through: :account_predecessors, source: :predecessor
  has_many :account_successors, class_name: "AccountPredecessor", foreign_key: :predecessor_id, dependent: :destroy
  has_many :successors, through: :account_successors, source: :account
  has_many :transactions, dependent: :destroy
  has_many :imports, dependent: :destroy

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  def liquid? = kind.in?(LIQUID)

  def loan? = kind == "loan"

  scope :active, -> { where(active: true) }
  scope :liquid, -> { where(kind: LIQUID) }
  scope :joint, -> { where(owner_id: nil) }

  def balance_cents(on: nil)
    # Before opened_on the account doesn't exist — its opening balance
    # only counts from then (just as a closure zeroes it after).
    return 0 if on && opened_on && on < opened_on
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

  # Account ids whose real txns feed this account's drift sample —
  # itself plus every predecessor transitively, so a refinanced
  # account projects from the old accounts' spend history.
  def source_ids
    seen = []
    queue = [ self ]
    until queue.empty?
      a = queue.shift
      next if seen.include?(a.id)
      seen << a.id
      queue.concat(a.predecessors)
    end
    seen
  end

  CLOSURE_PAYEE = "Account closure adjustment".freeze

  # Close this account out: post a one-sided closure adjustment
  # bringing the ledger to zero, then archive. With a `successor` the
  # recurring rules move across and the account joins its predecessor
  # set — the old history then feeds the successor's forecast. The
  # successor's own balance is untouched: its opening/actuals are
  # already the truth.
  def handover_to!(successor = nil, on: nil)
    on ||= transactions.maximum(:posted_on) || Date.current
    Account.transaction do
      residual = balance_cents(on:)
      if residual != 0
        # Payee deliberately avoids transfer-ish words and account names
        # so pair_transfer! leaves it alone — it's one-sided plumbing.
        transactions.create!(posted_on: on, amount_cents: -residual,
                             payee: CLOSURE_PAYEE,
                             notes: ("Balance handed over to #{successor.name}" if successor),
                             category: closure_category, user: Current.user)
      end
      link_successor!(successor, on:) if successor
      update!(active: false)
    end
  end

  # Attach a successor after the fact (or as part of handover): the
  # link is recorded, this account's remaining rules move across, and
  # the successor's opened_on is pushed back to the handover date if
  # it isn't already earlier.
  def link_successor!(successor, on: nil)
    on ||= transactions.maximum(:posted_on) || Date.current
    Account.transaction do
      RecurringRule.where(account_id: id).update_all(account_id: successor.id)
      RecurringRule.where(to_account_id: id).update_all(to_account_id: successor.id)
      successor.account_predecessors.find_or_create_by!(predecessor: self)
      successor.update!(opened_on: [ successor.opened_on, on ].compact.min)
    end
  end

  # Move the closure to `on` — the adjustment txns and the successors'
  # opened_on follow. opened_on only ever moves earlier; for a later
  # date, edit the successor's own Opened on field.
  def redate_closure!(on)
    Account.transaction do
      transactions.where(payee: CLOSURE_PAYEE).update_all(posted_on: on)
      successors.each { |s| s.update!(opened_on: [ s.opened_on, on ].compact.min) }
    end
  end

  private

  # Settlement adjustments are plumbing, not spend — same exclusion as
  # the one-off categories, kept out of every drift sample.
  def closure_category
    Category.find_or_create_by!(name: "Account closure", kind: "expense") do |c|
      c.exclude_from_forecast = true
    end
  end
end
