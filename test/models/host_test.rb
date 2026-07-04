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

  test "rejects duplicate ICMP address in same group" do
    existing = hosts(:one)
    duplicate = Host.new(name: "Dupe", address: existing.address, probe_type: :icmp,
                         interval: 60, group: existing.group)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:address], "is already monitored in this group with the same probe type"
  end

  test "allows same address with different probe types in same group" do
    existing = hosts(:one)
    http_host = Host.new(name: "HTTP version", address: "example.com", probe_type: :http,
                         interval: 60, group: existing.group)

    assert http_host.valid?
  end

  test "allows same TCP address on different ports in same group" do
    group = groups(:one)
    Host.create!(name: "SSH", address: "server.local", probe_type: :tcp, port: 22, interval: 60, group: group)

    mysql = Host.new(name: "MySQL", address: "server.local", probe_type: :tcp, port: 3306, interval: 60, group: group)

    assert mysql.valid?
  end

  test "rejects duplicate TCP address+port in same group" do
    group = groups(:one)
    Host.create!(name: "SSH", address: "server.local", probe_type: :tcp, port: 22, interval: 60, group: group)

    dupe = Host.new(name: "SSH dupe", address: "server.local", probe_type: :tcp, port: 22, interval: 60, group: group)

    assert_not dupe.valid?
    assert_includes dupe.errors[:address], "is already monitored on port 22 in this group"
  end

  test "rejects probe type change on existing host" do
    host = hosts(:one)
    host.probe_type = :http

    assert_not host.valid?
    assert_includes host.errors[:probe_type], "cannot be changed after the host is created"
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
