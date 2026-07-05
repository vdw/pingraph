require "test_helper"

class ProbeServiceNotificationsTest < ActiveJob::TestCase
  setup do
    @host = hosts(:one) # icmp
    @host.update_columns(
      status: Host.statuses[:up],
      last_notified_status: Host.last_notified_statuses[:up],
      consecutive_failures: 0,
      notifications_enabled: true,
      notify_on_degraded: false
    )
  end

  def fail_result
    ProbeService::Result.new(probe_type: :icmp, success: false, packet_loss: 100, error_message: "100% packet loss", metadata: {}, recorded_at: Time.current)
  end

  def ok_result
    ProbeService::Result.new(probe_type: :icmp, success: true, latency: 10.0, packet_loss: 0, metadata: {}, recorded_at: Time.current)
  end

  # Replaces the real ICMP probe (which shells out to `ping`) with a queue of results.
  def stub_probe_icmp(results)
    original = ProbeService.method(:probe_icmp)
    ProbeService.singleton_class.define_method(:probe_icmp) { |_host| results.shift }
    yield
  ensure
    ProbeService.singleton_class.define_method(:probe_icmp, original)
  end

  test "confirmed Down alerts once, a repeat Down does not, and recovery alerts" do
    stub_probe_icmp([ fail_result, fail_result, fail_result, ok_result ]) do
      # 1st failure -> degraded (pending down); suppressed because notify_on_degraded is false
      assert_enqueued_jobs 0, only: DeliverNotificationJob do
        ProbeService.execute(@host)
      end
      @host.reload
      assert_equal "degraded", @host.status
      assert_equal "up", @host.last_notified_status

      # 2nd failure -> confirmed Down: exactly one alert
      assert_enqueued_jobs 1, only: DeliverNotificationJob do
        ProbeService.execute(@host)
      end
      @host.reload
      assert_equal "down", @host.status
      assert_equal "down", @host.last_notified_status

      # 3rd failure -> still Down: no new alert (de-duplicated)
      assert_enqueued_jobs 0, only: DeliverNotificationJob do
        ProbeService.execute(@host)
      end

      # recovery -> Up: alert fires
      assert_enqueued_jobs 1, only: DeliverNotificationJob do
        ProbeService.execute(@host)
      end
      assert_equal "up", @host.reload.last_notified_status
    end
  end

  test "enqueued job carries a serializable payload snapshot" do
    stub_probe_icmp([ fail_result, fail_result ]) do
      ProbeService.execute(@host) # -> degraded, suppressed
      assert_enqueued_with(job: DeliverNotificationJob) do
        ProbeService.execute(@host) # -> down
      end
    end

    args = enqueued_jobs.find { |j| j[:job] == DeliverNotificationJob }[:args].first
    payload = NotificationPayload.from_job_args(args)
    assert_equal @host.name, payload.host_name
    assert_equal :down, payload.event
  end
end
