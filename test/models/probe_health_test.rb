require "test_helper"

class ProbeHealthTest < ActiveSupport::TestCase
  # The test environment uses a null cache store; the counters need a real one.
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "stalled when hosts exist and the poller has never run or not recently" do
    freeze_time do
      Setting.current.update_columns(poller_heartbeat_at: nil)
      assert ProbeHealth.stalled?

      ProbeHealth.record_poll!(1.minute.ago)
      assert_not ProbeHealth.stalled?

      ProbeHealth.record_poll!(4.minutes.ago)
      assert ProbeHealth.stalled?
    end
  end

  test "not stalled without hosts" do
    Host.destroy_all
    Setting.current.update_columns(poller_heartbeat_at: nil)

    assert_not ProbeHealth.stalled?
  end

  test "falling behind once enough probes, and a large enough share, start late" do
    freeze_time do
      40.times { ProbeHealth.record_probe!(late: false) }
      9.times { ProbeHealth.record_probe!(late: true) }
      assert_not ProbeHealth.falling_behind?, "fewer than the minimum late probes"

      ProbeHealth.record_probe!(late: true)
      assert ProbeHealth.falling_behind?

      assert_equal({ late: 10, total: 50 }, ProbeHealth.probe_counts)
    end
  end

  test "a burst of late probes among many on-time ones is not falling behind" do
    freeze_time do
      200.times { ProbeHealth.record_probe!(late: false) }
      20.times { ProbeHealth.record_probe!(late: true) }

      assert_not ProbeHealth.falling_behind?
    end
  end

  test "counts cover the current and previous hour only" do
    freeze_time do
      ProbeHealth.record_probe!(late: true, at: 3.hours.ago)
      ProbeHealth.record_probe!(late: true, at: 1.hour.ago)
      ProbeHealth.record_probe!(late: false)

      assert_equal({ late: 1, total: 2 }, ProbeHealth.probe_counts)
    end
  end
end
