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

  test "status badge reflects the persisted status, not a single latest sample" do
    host = hosts(:one)
    host.update_columns(status: Host.statuses.fetch("up"), latency_threshold_ms: 200.0, updated_at: Time.current)
    host.probe_results.create!(probe_type: :icmp, success: true, latency: 245.0, packet_loss: 0, recorded_at: Time.current)

    assert_equal :up, host.status_badge

    host.update_columns(status: Host.statuses.fetch("degraded"))
    assert_equal :degraded, host.status_badge
  end

  test "one lost packet out of five is not a problem sample, two are" do
    host = hosts(:one)

    assert_not host.result_degraded?(ProbeResult.new(probe_type: :icmp, success: true, latency: 5.0, packet_loss: 20))
    assert host.result_degraded?(ProbeResult.new(probe_type: :icmp, success: true, latency: 5.0, packet_loss: 40))
  end

  test "icmp and tcp addresses must be a hostname or IP" do
    host = hosts(:one)

    %w[192.168.1.1 8.8.8.8 ::1 2001:db8::1 nas.local router my-server.example.com].each do |address|
      host.address = address
      assert host.valid?, "#{address} should be valid: #{host.errors.full_messages.join(', ')}"
    end

    [ "-f", "--flood", "1.1.1.1; rm -rf /", "10.0.0.0/24", "http://x", "a b", "bad_host" ].each do |address|
      host.address = address
      assert_not host.valid?, "#{address} should be invalid"
      assert host.errors[:address].any?
    end
  end

  test "address is stripped before validation" do
    host = hosts(:one)
    host.address = "  8.8.4.4  "
    assert host.valid?
    assert_equal "8.8.4.4", host.address
  end

  test "tcp address with an embedded port points at the port field" do
    host = Host.new(name: "Web", address: "192.168.1.10:443", probe_type: :tcp, port: 443, interval: 60, group: groups(:one))

    assert_not host.valid?
    assert_includes host.errors[:address].join, "Port field"
  end

  test "changing the interval resets the probe schedule" do
    host = hosts(:one)
    host.update_columns(next_probe_at: 10.minutes.from_now)

    host.update!(name: "Renamed")
    assert_not_nil host.reload.next_probe_at

    host.update!(interval: 30)
    assert_nil host.reload.next_probe_at
  end

  test "destroying a host removes its history in bulk" do
    host = hosts(:one)
    3.times { |i| host.probe_results.create!(probe_type: :icmp, success: true, latency: 1.0, packet_loss: 0, recorded_at: i.minutes.ago) }
    delivery = NotificationDelivery.create!(host: host, channel: "slack", event: "down", payload: { "host_name" => host.name })

    assert_difference("ProbeResult.count", -host.probe_results.count) do
      host.destroy!
    end

    assert_nil delivery.reload.host_id, "the notification log keeps entries for deleted hosts"
    assert_equal host.name, delivery.host_name
  end
end
