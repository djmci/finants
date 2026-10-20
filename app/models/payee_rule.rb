class PayeeRule < ApplicationRecord
  belongs_to :category

  validates :pattern, presence: true, uniqueness: true

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
  def self.for(payee)
    key = detection_key(payee)
    raw = normalize(payee)
    return nil if key.blank? && raw.blank?
    includes(:category)
      .select { |r| key.include?(r.pattern) || raw.include?(r.pattern) }
      .max_by { |r| r.pattern.length }&.category
  end

  def self.learn(payee, category)
    return if payee.blank? || category.nil?
    find_or_initialize_by(pattern: detection_key(payee).presence || normalize(payee)).update!(category:)
  end
end
