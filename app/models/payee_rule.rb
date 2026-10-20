class PayeeRule < ApplicationRecord
  belongs_to :category

  validates :pattern, presence: true, uniqueness: { scope: %i[round_amount max_amount_cents] }

  before_validation { self.pattern = self.class.normalize(pattern) }

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
  # amounts only; `max_amount_cents` caps the magnitude, spends only —
  # e.g. sub-$20 kid top-ups are eating out, larger transfers aren't.
  def self.for(payee, amount_cents: nil)
    key = detection_key(payee)
    raw = normalize(payee)
    return nil if key.blank? && raw.blank?
    matches = includes(:category).select { |r| key.include?(r.pattern) || raw.include?(r.pattern) }
    if amount_cents
      round = (amount_cents % 100).zero?
      # Conditions gate a rule: flag mismatch or magnitude over cap
      # means the rule doesn't apply to this transaction at all.
      matches = matches.select do |r|
        (r.round_amount.nil? || r.round_amount == round) &&
          (r.max_amount_cents.nil? || (amount_cents.negative? && amount_cents.abs <= r.max_amount_cents))
      end
    else
      matches = matches.select { |r| r.round_amount.nil? && r.max_amount_cents.nil? }
    end
    # More conditions = more specific; then longest pattern wins.
    matches.max_by { |r| [ (r.round_amount.nil? ? 0 : 1) + (r.max_amount_cents ? 1 : 0), r.pattern.length ] }
           &.category
  end

  def self.learn(payee, category, amount_cents = nil)
    return if payee.blank? || category.nil?
    round = amount_cents && (amount_cents % 100).zero?
    find_or_initialize_by(pattern: detection_key(payee).presence || normalize(payee),
                          round_amount: round).update!(category:)
  end
end
