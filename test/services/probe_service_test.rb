require "test_helper"

class ProbeServiceTest < ActiveSupport::TestCase
  test "probe_http respects verify_ssl false for self-signed endpoints" do
    host = hosts(:one)
    host.update_columns(
      probe_type: Host.probe_types.fetch("http"),
      address: "https://internal.local",
      expected_status_code: 200,
      expected_status_code_range: "exact",
      verify_ssl: false,
      updated_at: Time.current
    )

    fake_response = Struct.new(:code, :message).new("200", "OK")
    fake_http = FakeHttp.new(fake_response)

    original_new = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new, ->(_host, _port) { fake_http })

    result = ProbeService.probe_http(host)

    assert result.success
    assert_equal OpenSSL::SSL::VERIFY_NONE, fake_http.verify_mode
    assert_equal 200, result.status_code
  ensure
    Net::HTTP.singleton_class.define_method(:new, original_new)
  end

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
      assert_includes result.error_message, "Connection refused"
    end

    host.reload
    assert_equal "degraded", host.status
    assert_equal 1, host.consecutive_failures
    assert_not_nil host.last_error_message
  ensure
    Socket.singleton_class.define_method(:tcp, original_tcp)
  end

  test "probe_http returns failure when status mismatches expected range" do
    host = hosts(:one)
    host.update_columns(
      probe_type: Host.probe_types.fetch("http"),
      address: "https://service.local",
      expected_status_code: 200,
      expected_status_code_range: "exact",
      verify_ssl: true,
      updated_at: Time.current
    )

    fake_response = Struct.new(:code, :message).new("404", "Not Found")
    fake_http = FakeHttp.new(fake_response)

    original_new = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new, ->(_host, _port) { fake_http })

    result = ProbeService.probe_http(host)

    assert_not result.success
    assert_equal 404, result.status_code
    assert_not_nil result.latency
    assert_equal "Unexpected HTTP status 404", result.error_message
  ensure
    Net::HTTP.singleton_class.define_method(:new, original_new)
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

    assert_difference("host.probe_results.count", +1) do
      ProbeService.send(:persist_result!, host, result)
    end

    host.reload
    assert_equal "degraded", host.status
    assert_equal 0, host.consecutive_failures
    assert_nil host.last_error_message
  end

  class FakeHttp
    attr_accessor :open_timeout, :read_timeout, :use_ssl, :verify_mode

    def initialize(response)
      @response = response
    end

    def request(_request)
      @response
    end
  end
end
