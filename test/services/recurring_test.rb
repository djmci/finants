require "test_helper"

class RecurringTest < ActiveSupport::TestCase
  test "weekly occurrences fire on the anchor weekday" do
    rule = RecurringRule.new(frequency: "weekly", every: 1, start_on: Date.new(2026, 10, 5)) # Monday
    dates = Recurring.occurrences(rule, Date.new(2026, 10, 1)..Date.new(2026, 10, 31))
    assert_equal [ 5, 12, 19, 26 ].map { |d| Date.new(2026, 10, d) }, dates
  end

  test "fortnightly occurrences every 14 days from anchor" do
    rule = recurring_rules(:paycheck) # starts 2 Oct
    dates = Recurring.occurrences(rule, Date.new(2026, 10, 1)..Date.new(2026, 11, 30))
    assert_equal [ Date.new(2026, 10, 2), Date.new(2026, 10, 16), Date.new(2026, 10, 30), Date.new(2026, 11, 13), Date.new(2026, 11, 27) ], dates
  end

  test "monthly clamps day-of-month then resumes anchor day" do
    rule = recurring_rules(:streaming) # every month on the 31st
    dates = Recurring.occurrences(rule, Date.new(2026, 1, 1)..Date.new(2026, 4, 30))
    assert_equal [ Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30) ], dates
  end

  test "every N months honours the interval" do
    rule = RecurringRule.new(frequency: "monthly", every: 3, start_on: Date.new(2026, 1, 10))
    dates = Recurring.occurrences(rule, Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
    assert_equal [ Date.new(2026, 1, 10), Date.new(2026, 4, 10), Date.new(2026, 7, 10), Date.new(2026, 10, 10) ], dates
  end

  test "range mid-schedule does not reset the anchor" do
    rule = RecurringRule.new(frequency: "weekly", every: 1, start_on: Date.new(2026, 1, 5))
    dates = Recurring.occurrences(rule, Date.new(2026, 3, 1)..Date.new(2026, 3, 31))
    assert_equal Date.new(2026, 3, 2), dates.first # Mondays, not March 1st + 7
  end

  test "end_on caps occurrences" do
    rule = RecurringRule.new(frequency: "weekly", every: 1, start_on: Date.new(2026, 10, 5), end_on: Date.new(2026, 10, 12))
    dates = Recurring.occurrences(rule, Date.new(2026, 10, 1)..Date.new(2026, 12, 31))
    assert_equal [ Date.new(2026, 10, 5), Date.new(2026, 10, 12) ], dates
  end
end
