class PayeeRule < ApplicationRecord
  belongs_to :category, optional: true
  # When set, this pattern marks spend the recurring rule covers — the
  # txns link to the rule and stay out of the drift sample.
  belongs_to :recurring_rule, optional: true

  DIRECTIONS = %w[in out].freeze

  validates :pattern, presence: true,
            uniqueness: { scope: %i[round_amount max_amount_cents direction] }
  validates :direction, inclusion: { in: DIRECTIONS }, allow_nil: true
  validate :category_or_coverage

  before_validation { self.pattern = self.class.normalize(pattern) }
  after_save :apply_to_uncategorised, if: -> { auto? && category_id.present? && saved_changes.slice("pattern", "category_id", "round_amount", "max_amount_cents", "direction", "auto").present? }

  def self.normalize(payee)
    # NBSP and friends show up in real bank exports — fold to ASCII space.
    payee.to_s.gsub(/[\s\u00A0\u2007\u202F]+/, " ").strip.upcase
  end

  # Ref-stripped matching key — drops every token containing a digit
  # (statement refs, timestamps, account numbers) so bank descriptions
  # group together and match durable payee patterns.
  def self.detection_key(payee)
    normalize(payee).gsub(/\b\w*\d\w*\b/, "").gsub(/\s+/, " ").strip
  end

  # Longest matching pattern wins. New rules store ref-stripped
  # detection keys (per-txn refs would never repeat); legacy full-payee
  # patterns still match against the raw normalized payee.
  # Conditions narrow a rule: `round_amount` matches .00 (or non-.00)
  # amounts only; `max_amount_cents` caps the magnitude, spends only;
  # `direction` requires in/out — e.g. incoming Osko is a payback,
  # outgoing Osko isn't.
  # auto_only: rules allowed to categorise silently at import —
  # non-auto rules only power the suggestion pills on History.
  def self.for(payee, amount_cents: nil, auto_only: false)
    best_rule_for(payee, amount_cents:, auto_only:, scope: where.not(category_id: nil))&.category
  end

  # The recurring rule covering this payee, if any — coverage rows are
  # pattern-only (amount conditions don't gate what a rule explains).
  def self.coverage_for(payee)
    best_rule_for(payee, scope: where.not(recurring_rule_id: nil))&.recurring_rule
  end

  def self.best_rule_for(payee, amount_cents: nil, auto_only: false, scope: all)
    key = detection_key(payee)
    raw = normalize(payee)
    return nil if key.blank? && raw.blank?
    matches = scope.includes(:category, :recurring_rule).select { |r| key.include?(r.pattern) || raw.include?(r.pattern) }
    matches = matches.select(&:auto) if auto_only
    if amount_cents
      round = (amount_cents % 100).zero?
      direction = amount_cents.negative? ? "out" : "in"
      # Conditions gate a rule: flag mismatch, magnitude over cap, or
      # wrong direction means the rule doesn't apply at all.
      matches = matches.select do |r|
        (r.round_amount.nil? || r.round_amount == round) &&
          (r.max_amount_cents.nil? || (amount_cents.negative? && amount_cents.abs <= r.max_amount_cents)) &&
          (r.direction.nil? || r.direction == direction)
      end
    else
      matches = matches.select { |r| r.round_amount.nil? && r.max_amount_cents.nil? && r.direction.nil? }
    end
    # More conditions = more specific; then longest pattern wins.
    matches.max_by { |r| [ r.conditions, r.pattern.length ] }
  end

  def self.learn(payee, category, amount_cents = nil)
    return if payee.blank? || category.nil?
    round = amount_cents && (amount_cents % 100).zero?
    find_or_initialize_by(pattern: detection_key(payee).presence || normalize(payee),
                          round_amount: round).update!(category:)
  end

  def conditions
    [ round_amount, max_amount_cents, direction ].count(&:present?)
  end

  # Tags every uncategorised txn this rule wins on — runs after save so
  # "auto" rules take effect immediately, not just on the next import.
  # update_column skips callbacks, so no learn-feedback loop.
  def apply_to_uncategorised
    scope = self.class.where.not(category_id: nil)
    Transaction.uncategorised.find_each do |t|
      t.update_column(:category_id, category_id) if self.class.best_rule_for(t.payee, amount_cents: t.amount_cents, scope:) == self
    end
  end

  private

  def category_or_coverage
    errors.add(:base, "Rule needs a category or a forecast rule") if category_id.nil? && recurring_rule_id.nil?
  end
end
