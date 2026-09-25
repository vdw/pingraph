require "test_helper"

class ProbeServicePersistenceTest < ActiveSupport::TestCase
  setup do
    @host = hosts(:one) # icmp
    @host.update_columns(status: Host.statuses[:up], consecutive_failures: 0, consecutive_issues: 0)
  end

  def stub_ping(stdout:, stderr: "", exitstatus: 0)
    seen = nil
    original = Open3.method(:capture3)
    Open3.singleton_class.define_method(:capture3) do |*args|
      seen = args
      [ stdout, stderr, Struct.new(:exitstatus).new(exitstatus) ]
    end
    yield -> { seen }
  ensure
    Open3.singleton_class.define_method(:capture3, original)
  end

  def ok_result(packet_loss: 0, latency: 5.0)
    ProbeService::Result.new(probe_type: :icmp, success: true, latency: latency, packet_loss: packet_loss, metadata: {}, recorded_at: Time.current)
  end

  def fail_result
    ProbeService::Result.new(probe_type: :icmp, success: false, packet_loss: 100, metadata: {}, recorded_at: Time.current)
  end

  test "a database error while saving raises instead of being recorded as a host failure" do
    original_run_probe = ProbeService.method(:run_probe)
    ProbeService.singleton_class.define_method(:run_probe) { |_host| ProbeService::Result.new(probe_type: :icmp, success: true, latency: 1.0, packet_loss: 0, metadata: {}, recorded_at: Time.current) }
    # The old code rescued this and saved a second "host failed" result with the DB error.
    @host.probe_results.singleton_class.define_method(:create!) { |*| raise ActiveRecord::StatementTimeout, "database is locked" }

    assert_no_difference("ProbeResult.count") do
      assert_raises(ActiveRecord::StatementTimeout) { ProbeService.execute(@host) }
    end
    assert_equal 0, @host.reload.consecutive_failures
    assert_equal "up", @host.status
  ensure
    ProbeService.singleton_class.define_method(:run_probe, original_run_probe)
  end

  test "ping gets the address after -- so it can never be read as an option" do
    stub_ping(stdout: "5 packets transmitted, 5 received, 0% packet loss\nrtt min/avg/max/mdev = 1.0/2.0/3.0/0.5 ms\n") do |seen|
      ProbeService.probe_icmp(@host)
      args = seen.call
      assert_equal [ "--", @host.address ], args.last(2)
    end
  end

  test "ping parses latency and keeps jitter" do
    stub_ping(stdout: "5 packets transmitted, 4 received, 20% packet loss, time 4005ms\nrtt min/avg/max/mdev = 10.111/12.222/15.333/1.444 ms\n", exitstatus: 0) do
      result = ProbeService.probe_icmp(@host)

      assert result.success
      assert_equal 20, result.packet_loss
      assert_in_delta 12.222, result.latency
      assert_in_delta 10.111, result.min_latency
      assert_in_delta 15.333, result.max_latency
      assert_in_delta 1.444, result.jitter
      assert_nil result.error_message
    end
  end

  test "ping errors keep their reason" do
    stub_ping(stdout: "", stderr: "ping: nas.local: Name or service not known\n", exitstatus: 2) do
      result = ProbeService.probe_icmp(@host)

      assert_not result.success
      assert_equal "nas.local: Name or service not known", result.error_message
    end
  end

  test "100% packet loss says so" do
    stub_ping(stdout: "5 packets transmitted, 0 received, 100% packet loss, time 4090ms\n", exitstatus: 1) do
      result = ProbeService.probe_icmp(@host)

      assert_not result.success
      assert_equal "No reply (100% packet loss)", result.error_message
    end
  end

  test "jitter is stored with the result" do
    ProbeService.send(:persist_result!, @host, ok_result.tap { |r| r.jitter = 0.75 })
    assert_equal 0.75, @host.probe_results.order(:id).last.jitter
  end

  test "one lost packet, one slow sample or one failure never changes the status" do
    [ ok_result(packet_loss: 20), ok_result(latency: 999.0), fail_result, ok_result(packet_loss: 40) ].each do |result|
      ProbeService.send(:persist_result!, @host, result)
      assert_equal "up", @host.reload.status
      ProbeService.send(:persist_result!, @host, ok_result)
    end
  end

  test "two problem samples in a row turn the host degraded, a clean one recovers it" do
    ProbeService.send(:persist_result!, @host, ok_result(latency: 999.0))
    ProbeService.send(:persist_result!, @host, ok_result(packet_loss: 60))
    assert_equal "degraded", @host.reload.status

    ProbeService.send(:persist_result!, @host, ok_result)
    assert_equal "up", @host.reload.status
    assert_equal 0, @host.consecutive_issues
  end

  test "two failures in a row turn the host down" do
    2.times { ProbeService.send(:persist_result!, @host, fail_result) }
    assert_equal "down", @host.reload.status

    ProbeService.send(:persist_result!, @host, ok_result(latency: 999.0))
    assert_equal "degraded", @host.reload.status, "a slow recovery is still a problem streak"
  end
end
