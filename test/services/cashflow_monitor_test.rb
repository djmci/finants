require "test_helper"

class CashflowMonitorTest < ActiveSupport::TestCase
  setup do
    @monitor = CashflowMonitor.new(warn: 5000, critical: 0)
  end

  def pts(pairs)
    pairs.map { |d, c| [ Date.new(2026, 1, 1) + (d - 1), c ] }
  end

  test "clean series has no breaches" do
    assert_empty @monitor.breaches(pts([ [ 1, 10000 ], [ 2, 20000 ] ]))
  end

  test "contiguous days below warn collapse into one breach" do
    b = @monitor.breaches(pts([ [ 1, 4000 ], [ 2, 3000 ], [ 3, 4500 ], [ 4, 9000 ], [ 5, 2000 ] ]))
    assert_equal 2, b.size
    assert_equal Date.new(2026, 1, 1), b[0].from
    assert_equal Date.new(2026, 1, 3), b[0].through
    assert_equal 3000, b[0].min
    assert_equal Date.new(2026, 1, 2), b[0].min_date
    assert_equal :warn, b[0].severity
    assert_equal Date.new(2026, 1, 5), b[1].from
  end

  test "a breach under the critical threshold is critical" do
    b = @monitor.breaches(pts([ [ 1, 4000 ], [ 2, -500 ], [ 3, 4000 ] ]))
    assert_equal 1, b.size
    assert_equal :critical, b[0].severity
    assert_equal(-500, b[0].min)
  end

  test "severity_of reflects worst point in window" do
    assert_equal :ok, @monitor.severity_of(pts([ [ 1, 9999 ] ]))
    assert_equal :warn, @monitor.severity_of(pts([ [ 1, 4999 ] ]))
    assert_equal :critical, @monitor.severity_of(pts([ [ 1, -1 ] ]))
  end
end
