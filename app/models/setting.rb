class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.[](key)
    find_by(key:)&.value
  end

  def self.[]=(key, value)
    find_or_initialize_by(key:).tap { |s| s.update!(value:) }
  end

  # Cash alert thresholds, cents.
  DEFAULT_WARN = 500_000
  DEFAULT_CRITICAL = 0

  def self.alert_warn_cents = (self["alert_warn_cents"] || DEFAULT_WARN).to_i
  def self.alert_critical_cents = (self["alert_critical_cents"] || DEFAULT_CRITICAL).to_i
  def self.set_alerts(warn:, critical:)
    self["alert_warn_cents"] = warn.to_i
    self["alert_critical_cents"] = critical.to_i
  end
end
