require "test_helper"

class AlertEvaluatorTest < ActiveSupport::TestCase
  setup do
    @host = hosts(:one)
    @host.update_columns(
      notifications_enabled: true,
      notify_on_degraded: false,
      last_notified_status: Host.last_notified_statuses[:up]
    )
  end

  def result(success:, **opts)
    ProbeService::Result.new(probe_type: :icmp, success: success, metadata: {}, recorded_at: Time.current, **opts)
  end

  def set_baseline(status)
    @host.update_columns(last_notified_status: Host.last_notified_statuses[status])
  end

  test "up -> down fires a Down alert and advances the baseline" do
    payload = AlertEvaluator.evaluate(@host, result(success: false, error_message: "timeout"), :down)

    assert_not_nil payload
    assert_equal :down, payload.event
    assert_equal "down", @host.reload.last_notified_status
  end

  test "degraded -> down fires a Down alert" do
    set_baseline(:degraded)
    payload = AlertEvaluator.evaluate(@host, result(success: false), :down)

    assert_equal :down, payload&.event
    assert_equal "down", @host.reload.last_notified_status
  end

  test "down -> up fires a Recovery alert" do
    set_baseline(:down)
    payload = AlertEvaluator.evaluate(@host, result(success: true, latency: 12.0), :up)

    assert_equal :recovery, payload&.event
    assert_equal "up", @host.reload.last_notified_status
  end

  test "unknown -> up does not alert (host merely came online)" do
    set_baseline(:unknown)

    assert_nil AlertEvaluator.evaluate(@host, result(success: true, latency: 5.0), :up)
    assert_equal "unknown", @host.reload.last_notified_status
  end

  test "same status is de-duplicated" do
    set_baseline(:down)

    assert_nil AlertEvaluator.evaluate(@host, result(success: false), :down)
  end

  test "degraded is suppressed when notify_on_degraded is false, without advancing baseline" do
    assert_nil AlertEvaluator.evaluate(@host, result(success: true, latency: 999.0), :degraded)
    assert_equal "up", @host.reload.last_notified_status
  end

  test "degraded fires when notify_on_degraded is true" do
    @host.update_columns(notify_on_degraded: true)
    payload = AlertEvaluator.evaluate(@host, result(success: true, latency: 999.0), :degraded)

    assert_equal :degraded, payload&.event
    assert_equal "degraded", @host.reload.last_notified_status
  end

  test "no alert when notifications are disabled for the host" do
    @host.update_columns(notifications_enabled: false)

    assert_nil AlertEvaluator.evaluate(@host, result(success: false), :down)
  end

  test "payload carries host context and event details" do
    @host.update_columns(latency_threshold_ms: 100)
    payload = AlertEvaluator.evaluate(@host, result(success: false, error_message: "100% packet loss", packet_loss: 100), :down)

    assert_equal @host.name, payload.host_name
    assert_equal @host.group.name, payload.group_name
    assert_equal 100, payload.packet_loss
    assert_equal "100% packet loss", payload.error_message
  end
end
