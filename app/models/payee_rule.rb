class PayeeRule < ApplicationRecord
  belongs_to :category

  validates :pattern, presence: true, uniqueness: true

  before_validation { self.pattern = self.class.normalize(pattern) }

  def self.normalize(payee)
    payee.to_s.gsub(/\s+/, " ").strip.upcase
  end

  # Longest matching pattern wins; pattern is a substring of the payee.
  def self.for(payee)
    upcased = normalize(payee)
    return nil if upcased.blank?
    includes(:category).select { |r| upcased.include?(r.pattern) }.max_by { |r| r.pattern.length }&.category
  end

  def self.learn(payee, category)
    return if payee.blank? || category.nil?
    find_or_initialize_by(pattern: normalize(payee)).update!(category:)
  end
end
