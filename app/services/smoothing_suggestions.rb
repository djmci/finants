# Given a projected balance series and the rules that drive it, find
# the days the balance dips low, then suggest moving the big outflows
# that precede the dip to just after the next income occurrence.
class SmoothingSuggestions
  LOOKBACK = 10 # days before a trough to hunt for movable outflows

  def initialize(points:, rules:, warn_cents:)
    @points = points            # [[Date, cents], ...]
    @rules = rules
    @warn = warn_cents
  end

  # [{ payee:, current_dates:, suggested_date:, amount_cents:, trough: }]
  def call
    troughs = @points.select { |_, v| v < @warn }.map(&:first)
    troughs = [ @points.min_by(&:last).first ] if troughs.empty? && @points.any?
    return [] if troughs.empty?

    inflow_dates = rules_by_kind("income").flat_map { |r| Recurring.occurrences(r, range) }
    return [] if inflow_dates.empty?

    troughs.first(3).filter_map do |d|
      movable = biggest_outflow_before(d)
      next unless movable
      payday = inflow_dates.select { |i| i > d }.min
      next unless payday
      { rule: movable[:rule], on: movable[:on], trough: d,
        suggested: payday + 1, amount_cents: movable[:amount_cents] }
    end.uniq { |s| s[:rule].id }
  end

  private

  def range = @points.first.first..@points.last.first

  def rules_by_kind(kind) = @rules.select { |r| r.kind == kind }

  # The largest non-income rule firing in the days before the trough —
  # the thing that could move. Settle rules report their dynamic amount
  # via the caller's projections elsewhere; here we use rule amount.
  def biggest_outflow_before(trough)
    window = (trough - LOOKBACK)..trough
    occurrences = Recurring.occurrences_for(
      @rules.select { |r| r.kind != "income" }, window
    )
    occurrences.min_by { |o| signed(o) }
               .then { |o| o && { rule: o[:rule], on: o[:on], amount_cents: signed(o).abs } }
  end

  # Any non-income rule drains cash by its magnitude — transfer/settle
  # rules can carry positive or zero amounts, so use absolute size.
  def signed(o) = -o[:rule].amount_cents.abs
end
