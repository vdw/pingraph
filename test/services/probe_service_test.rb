require "test_helper"

class ProbeServiceTest < ActiveSupport::TestCase
  test "execute stores tcp failure result and updates host status" do
    host = hosts(:one)
    host.update_columns(
      probe_type: Host.probe_types.fetch("tcp"),
      address: "127.0.0.1",
      port: 65535,
      status: Host.statuses.fetch("unknown"),
      consecutive_failures: 0,
      updated_at: Time.current
    )

    original_tcp = Socket.method(:tcp)
    Socket.singleton_class.define_method(:tcp, ->(*_args, **_kwargs, &_blk) { raise Errno::ECONNREFUSED })

    assert_difference("host.probe_results.count", +1) do
      result = ProbeService.execute(host)
      assert_not result.success
      assert_nil result.latency
      assert_includes result.error_message, "Connection refused"
    end

    host.reload
    # One failed check is not enough evidence to change state.
    assert_equal "unknown", host.status
    assert_equal 1, host.consecutive_failures
    assert_equal 1, host.consecutive_issues
    assert_not_nil host.last_error_message
  ensure
    Socket.singleton_class.define_method(:tcp, original_tcp)
  end

  test "execute stores degraded host status for successful high latency http probe" do
    host = hosts(:one)
    host.update_columns(
      probe_type: Host.probe_types.fetch("http"),
      address: "https://service.local",
      expected_status_code: 200,
      expected_status_code_range: "exact",
      verify_ssl: true,
      latency_threshold_ms: 200.0,
      status: Host.statuses.fetch("unknown"),
      consecutive_failures: 0,
      updated_at: Time.current
    )

    result = ProbeService::Result.new(
      probe_type: :http,
      success: true,
      latency: 245.0,
      status_code: 200,
      metadata: {},
      recorded_at: Time.current
    )

    assert_difference("host.probe_results.count", +2) do
      ProbeService.send(:persist_result!, host, result)
      assert_equal "unknown", host.reload.status, "a single slow sample must not flip the status"
      ProbeService.send(:persist_result!, host, result)
    end

    host.reload
    assert_equal "degraded", host.status
    assert_equal 0, host.consecutive_failures
    assert_nil host.last_error_message
  end
end
