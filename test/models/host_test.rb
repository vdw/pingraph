require "test_helper"

class HostTest < ActiveSupport::TestCase
  test "defaults latency threshold to 350ms" do
    host = Host.new(name: "Example", address: "example.com", interval: 60, group: groups(:one))

    host.valid?

    assert_equal 350.0, host.latency_threshold_ms
  end

  test "validates positive latency threshold" do
    host = hosts(:one)
    host.latency_threshold_ms = 0

    assert_not host.valid?
    assert_includes host.errors[:latency_threshold_ms], "must be greater than 0"
  end

  test "status badge marks successful high latency result as degraded" do
    host = hosts(:one)
    host.update_columns(status: Host.statuses.fetch("up"), latency_threshold_ms: 200.0, updated_at: Time.current)
    host.probe_results.create!(
      probe_type: :http,
      success: true,
      latency: 245.0,
      status_code: 200,
      recorded_at: Time.current
    )

    assert_equal :degraded, host.status_badge
  end
end
