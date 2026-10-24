require "test_helper"

class HeartbeatJobTest < ActiveJob::TestCase
  setup do
    Setting.current.update!(heartbeat_url: "https://hc-ping.example/abc123")
  end

  test "pings the heartbeat URL while probing is healthy" do
    ProbeHealth.record_poll!(30.seconds.ago)

    requests = with_stubbed_http { HeartbeatJob.perform_now }

    assert_equal [ [ "hc-ping.example", 443, "/abc123" ] ], requests
  end

  test "stays silent when probing has stalled, so the external service alerts" do
    ProbeHealth.record_poll!(10.minutes.ago)

    assert_empty with_stubbed_http { HeartbeatJob.perform_now }
  end

  test "does nothing without a heartbeat URL" do
    Setting.current.update!(heartbeat_url: "")
    ProbeHealth.record_poll!(30.seconds.ago)

    assert_empty with_stubbed_http { HeartbeatJob.perform_now }
  end

  test "a failed ping is logged, not raised" do
    ProbeHealth.record_poll!(30.seconds.ago)

    with_stubbed_http(error: Errno::ECONNREFUSED) do
      assert_nothing_raised { HeartbeatJob.perform_now }
    end
  end

  test "the heartbeat URL is encrypted and must be http(s)" do
    raw = Setting.connection.select_value("SELECT heartbeat_url FROM settings WHERE id = #{Setting.current.id}")
    assert_not_includes raw, "abc123"

    setting = Setting.current
    setting.heartbeat_url = "ftp://example.com"
    assert_not setting.valid?
    assert_includes setting.errors[:heartbeat_url], "must be a valid http(s):// URL"
  end

  private

  def with_stubbed_http(error: nil)
    requests = []
    fake_class = Class.new do
      attr_accessor :use_ssl, :open_timeout, :read_timeout

      define_method(:initialize) { |host, port| @host, @port = host, port }
      define_method(:request) do |request|
        raise error if error

        requests << [ @host, @port, request.path ]
        Net::HTTPOK.new("1.1", "200", "OK")
      end
    end

    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) { |host, port| fake_class.new(host, port) }
    yield
    requests
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end
end
