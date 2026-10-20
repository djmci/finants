class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  ROLES = %w[admin member].freeze

  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  def admin?
    role == "admin"
  end

  def initials
    name.to_s.split.first(2).map { |p| p[0] }.join.upcase.presence || "?"
  end
end
