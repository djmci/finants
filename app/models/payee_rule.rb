class PayeeRule < ApplicationRecord
  belongs_to :category

  validates :pattern, presence: true, uniqueness: { scope: :round_amount }

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
  # `round_amount` rules only apply when the amount ends in .00 (or
  # doesn't) — e.g. a round AGL bill is the mobile plan, not energy.
  def self.for(payee, amount_cents: nil)
    key = detection_key(payee)
    raw = normalize(payee)
    return nil if key.blank? && raw.blank?
    matches = includes(:category).select { |r| key.include?(r.pattern) || raw.include?(r.pattern) }
    if amount_cents
      round = (amount_cents % 100).zero?
      exact = matches.select { |r| r.round_amount == round }
      matches = exact.presence || matches.select { |r| r.round_amount.nil? }.presence || matches
    end
    matches.max_by { |r| r.pattern.length }&.category
  end

  def self.learn(payee, category, amount_cents = nil)
    return if payee.blank? || category.nil?
    round = amount_cents && (amount_cents % 100).zero?
    find_or_initialize_by(pattern: detection_key(payee).presence || normalize(payee),
                          round_amount: round).update!(category:)
  end
end
