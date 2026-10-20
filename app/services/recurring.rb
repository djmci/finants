# Pure occurrence generation for RecurringRules — no DB access beyond
# what the caller hands it. Dates only; money/display logic stays on
# the rule.
class Recurring
  # Dates a rule fires on within `range` (Range of Dates), honouring
  # start_on/end_on.
  def self.occurrences(rule, range)
    if rule.frequency == "once"
      # Fires once at start_on; if overdue-but-unresolved it projects at
      # today (could land any time); a passed end_on means it's dead.
      return [] if rule.end_on && rule.end_on < range.begin
      d = [ rule.start_on, range.begin ].max
      return d <= range.end ? [ d ] : []
    end
    first = [ range.begin, rule.start_on ].max
    last = [ range.end, rule.end_on ].compact.min
    return [] if first > last
    advance = advance_for(rule)
    dates = []
    d = rule.start_on
    dates << d if d >= first
    loop do
      d = advance.call(d)
      break if d > last
      dates << d if d >= first
    end
    dates
  end

  # [{ rule:, on: Date }] across many rules, sorted by date.
  def self.occurrences_for(rules, range)
    rules.flat_map { |r| occurrences(r, range).map { |on| { rule: r, on: } } }
         .sort_by { |o| o[:on] }
  end

  # Returns a lambda date -> next occurrence date (strictly after input).
  def self.advance_for(rule)
    case rule.frequency
    when "weekly"       then ->(d) { d + 7 * rule.every }
    when "fortnightly"  then ->(d) { d + 14 * rule.every }
    when "monthly"      then monthly_advance(rule)
    when "yearly"       then ->(d) { (d >> 12 * rule.every) }
    end
  end

  # Next monthly occurrence on the anchor's day-of-month, clamped to
  # month end (Jan 31 -> Feb 28 -> Mar 31).
  def self.monthly_advance(rule)
    anchor_day = rule.start_on.day
    ->(d) do
      months_since = (d.year - rule.start_on.year) * 12 + (d.month - rule.start_on.month)
      next_index = (months_since / rule.every + 1) * rule.every
      candidate = rule.start_on >> next_index
      day = [ anchor_day, Date.new(candidate.year, candidate.month, -1).day ].min
      Date.new(candidate.year, candidate.month, day)
    end
  end
end
