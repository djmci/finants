# Threshold monitor over a projected balance series — the "server
# monitor" for cash. Contiguous days under the warning threshold are
# grouped into one breach; a breach goes :critical if any day in it
# falls under the critical threshold.
class CashflowMonitor
  Breach = Struct.new(:severity, :from, :through, :min, :min_date, keyword_init: true)

  def initialize(warn:, critical:)
    @warn = warn
    @critical = critical
  end

  # points: [[Date, cents]] → [Breach]
  def breaches(points)
    runs = []
    points.each do |date, cents|
      if cents < @warn
        if runs.last && runs.last.through == date - 1
          runs.last.through = date
          if cents < runs.last.min
            runs.last.min = cents
            runs.last.min_date = date
          end
        else
          runs << Breach.new(severity: :warn, from: date, through: date, min: cents, min_date: date)
        end
      end
    end
    runs.each { |r| r.severity = :critical if r.min < @critical }
    runs
  end

  # Worst severity inside a window — for colouring the horizon stats.
  def severity_of(points)
    min = points.map(&:last).min
    return :critical if min && min < @critical
    return :warn if min && min < @warn
    :ok
  end
end
