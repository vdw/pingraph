require "test_helper"

class HostPollerJobTest < ActiveJob::TestCase
  setup do
    Host.update_all(next_probe_at: 1.day.from_now) # keep other fixtures out of the way
    @host = hosts(:one)
    clear_enqueued_jobs
  end

  def probe_times_for(host)
    enqueued_jobs
      .select { |job| job[:job] == ProbeJob && job[:args] == [ host.id ] }
      .map { |job| Time.at(job[:at]) }
      .sort
  end

  test "a new host is scheduled within the jitter window" do
    @host.update_columns(interval: 60, next_probe_at: nil)

    freeze_time do
      now = Time.current
      HostPollerJob.perform_now

      times = probe_times_for(@host)
      assert_equal 1, times.size
      assert_operator times.first, :>=, now
      assert_operator times.first, :<=, now + HostPollerJob::JITTER_MAX_SECONDS.seconds
      assert_in_delta (times.first + 60.seconds).to_f, @host.reload.next_probe_at.to_f, 0.001
    end
  end

  test "a host with an existing result is probed on its exact interval" do
    # The old poller compared against the last result's finish time and so waited an
    # extra minute: a 60s host was really checked every ~120s.
    freeze_time do
      @host.update_columns(interval: 60, next_probe_at: 30.seconds.from_now)
      @host.probe_results.create!(probe_type: :icmp, success: true, latency: 1.0, packet_loss: 0, recorded_at: 25.seconds.ago)

      HostPollerJob.perform_now

      assert_equal [ 30.seconds.from_now ], probe_times_for(@host)
      assert_equal 90.seconds.from_now, @host.reload.next_probe_at
    end
  end

  test "consecutive poller runs keep a steady 60s gap" do
    freeze_time do
      @host.update_columns(interval: 60, next_probe_at: 5.seconds.from_now)
      times = []

      3.times do
        clear_enqueued_jobs
        HostPollerJob.perform_now
        times.concat(probe_times_for(@host))
        travel HostPollerJob::POLL_PERIOD
      end

      assert_equal [ 60.0, 60.0 ], times.each_cons(2).map { |a, b| b - a }
    end
  end

  test "intervals under a minute get several probes per poller run" do
    freeze_time do
      @host.update_columns(interval: 10, next_probe_at: Time.current)

      HostPollerJob.perform_now

      times = probe_times_for(@host)
      assert_equal 6, times.size
      assert_equal [ 10.0 ] * 5, times.each_cons(2).map { |a, b| b - a }
      assert_equal 60.seconds.from_now, @host.reload.next_probe_at
    end
  end

  test "hosts not due in the coming minute are left alone" do
    freeze_time do
      @host.update_columns(interval: 300, next_probe_at: 2.minutes.from_now)

      HostPollerJob.perform_now

      assert_empty probe_times_for(@host)
      assert_equal 2.minutes.from_now, @host.reload.next_probe_at
    end
  end

  test "after downtime the schedule restarts instead of firing a burst of missed probes" do
    freeze_time do
      @host.update_columns(interval: 10, next_probe_at: 3.hours.ago)

      HostPollerJob.perform_now

      times = probe_times_for(@host)
      assert_includes 5..6, times.size # 6, unless the jitter lands exactly on 10s
      assert_operator times.first, :>=, Time.current
    end
  end
end
