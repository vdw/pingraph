require "test_helper"

class ProbeServiceHttpTest < ActiveSupport::TestCase
  setup do
    @host = Host.create!(group: groups(:one), name: "Web", probe_type: :http, address: "https://web.test/health", interval: 60)
    @routes = {}
    @connections = []
  end

  test "a matching status succeeds and records latency and the certificate expiry" do
    expires_at = 30.days.from_now.change(usec: 0)
    route "web.test", "/health", code: "200", certificate_expires_at: expires_at

    result = probe

    assert result.success
    assert_equal 200, result.status_code
    assert result.latency
    assert_equal expires_at, result.certificate_expires_at
    assert_equal OpenSSL::SSL::VERIFY_PEER, @connections.first.verify_mode
    assert_equal [ 5, 5, 5 ], @connections.first.timeouts
    assert_equal 0, @connections.first.max_retries
    assert_equal "Pingraph", @connections.first.requests.first["User-Agent"]
  end

  test "verify_ssl false and a custom timeout are applied" do
    @host.update!(verify_ssl: false, timeout_seconds: 12)
    route "web.test", "/health", code: "200"

    assert probe.success
    assert_equal OpenSSL::SSL::VERIFY_NONE, @connections.first.verify_mode
    assert_equal [ 12, 12, 12 ], @connections.first.timeouts
  end

  test "an unexpected status fails without latency" do
    route "web.test", "/health", code: "404"

    result = probe

    assert_not result.success
    assert_equal 404, result.status_code
    assert_nil result.latency, "failed checks must not be charted as latency"
    assert_not_nil result.metadata["elapsed_ms"]
    assert_equal "Unexpected HTTP status 404", result.error_message
  end

  test "follows redirects and matches the final status" do
    route "web.test", "/health", code: "301", location: "https://www.web.test/health"
    route "www.web.test", "/health", code: "302", location: "/status"
    route "www.web.test", "/status", code: "200"

    result = probe

    assert result.success, result.error_message
    assert_equal 200, result.status_code
    assert_equal 2, result.metadata["redirects"]
  end

  test "with redirects off, the redirect itself is the result" do
    @host.update!(max_redirects: 0, expected_status_code_range: "3xx")
    route "web.test", "/health", code: "301", location: "https://www.web.test/"

    result = probe

    assert result.success
    assert_equal 301, result.status_code
    assert_equal 1, @connections.size
  end

  test "too many redirects fail the check" do
    @host.update!(max_redirects: 1)
    route "web.test", "/health", code: "302", location: "/a"
    route "web.test", "/a", code: "302", location: "/b"

    result = probe

    assert_not result.success
    assert_equal "Too many redirects (more than 1)", result.error_message
  end

  test "a redirect to a non-http URL fails the check" do
    route "web.test", "/health", code: "302", location: "ftp://web.test/file"

    result = probe

    assert_not result.success
    assert_match(/unsupported URL/, result.error_message)
  end

  test "keyword checks look at the body, optionally inverted" do
    @host.update!(keyword: "All systems operational")
    route "web.test", "/health", code: "200", body: "<p>All systems operational</p>"
    assert probe.success

    route "web.test", "/health", code: "200", body: "<p>Partial outage</p>"
    result = probe
    assert_not result.success
    assert_equal %(Keyword "All systems operational" not found), result.error_message

    @host.update!(keyword: "outage", keyword_invert: true)
    result = probe
    assert_not result.success
    assert_equal %(Keyword "outage" was found), result.error_message
  end

  test "keywords match non-ASCII text" do
    @host.update!(keyword: "Λειτουργεί")
    route "web.test", "/health", code: "200", body: "<p>Λειτουργεί κανονικά</p>".b

    assert probe.success
  end

  test "sends the method, body, headers and basic auth to the monitored origin only" do
    @host.update!(http_method: "POST", request_body: '{"ping":true}', request_headers: "X-Api-Key: abc123\nAccept: application/json",
      basic_auth_user: "admin", basic_auth_password: "s3cret")
    route "web.test", "/health", code: "307", location: "https://other.test/health"
    route "other.test", "/health", code: "200"

    assert probe.success

    first, second = @connections.map { |connection| connection.requests.first }
    assert_equal "POST", first.method
    assert_equal '{"ping":true}', first.body
    assert_equal "application/json", first["Content-Type"]
    assert_equal "abc123", first["X-Api-Key"]
    assert_equal "application/json", first["Accept"]
    assert_equal "Basic #{Base64.strict_encode64('admin:s3cret')}", first["Authorization"]

    # 307 repeats the request, but never sends credentials to another host.
    assert_equal "POST", second.method
    assert_nil second["X-Api-Key"]
    assert_nil second["Authorization"]
  end

  test "a 303 after a POST becomes a GET without a body" do
    @host.update!(http_method: "POST", request_body: "hello")
    route "web.test", "/health", code: "303", location: "/done"
    route "web.test", "/done", code: "200"

    assert probe.success

    second = @connections.last.requests.first
    assert_equal "GET", second.method
    assert_nil second.body
    assert_equal "text/plain", @connections.first.requests.first["Content-Type"]
  end

  test "a timeout reports the configured timeout" do
    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) { |*_args| raise Net::ReadTimeout }

    result = ProbeService.probe_http(@host)

    assert_equal "Timed out after 5 seconds", result.error_message
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end

  test "connection errors fail the check" do
    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) { |*_args| raise Errno::ECONNREFUSED }

    result = ProbeService.probe_http(@host)

    assert_not result.success
    assert_includes result.error_message, "Connection refused"
    assert_equal "Errno::ECONNREFUSED", result.metadata["error_class"]
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end

  private

  def route(host, path, code:, body: "ok", location: nil, certificate_expires_at: nil)
    @routes[[ host, path ]] = { code: code, body: body, location: location, certificate_expires_at: certificate_expires_at }
  end

  def probe
    @connections.clear
    routes = @routes
    connections = @connections
    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) do |host, port|
      FakeConnection.new(host, routes).tap { |connection| connections << connection }
    end

    ProbeService.probe_http(@host)
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end

  class FakeConnection
    attr_accessor :open_timeout, :read_timeout, :write_timeout, :max_retries, :use_ssl, :verify_mode
    attr_reader :requests

    def initialize(host, routes)
      @host = host
      @routes = routes
      @requests = []
    end

    def timeouts = [ open_timeout, read_timeout, write_timeout ]

    def start
      yield self
    end

    def peer_cert
      expires_at = @routes.find { |(host, _path), _| host == @host }&.last&.dig(:certificate_expires_at)
      return nil unless expires_at

      OpenSSL::X509::Certificate.new.tap { |certificate| certificate.not_after = expires_at }
    end

    def request(request)
      @requests << request
      route = @routes.fetch([ @host, request.path ])
      response = Net::HTTPResponse::CODE_TO_OBJ.fetch(route[:code]).new("1.1", route[:code], "Stub")
      response["Location"] = route[:location] if route[:location]
      body = route[:body]
      response.define_singleton_method(:read_body) { |&block| block ? block.call(body) : body }
      response.define_singleton_method(:body) { body }
      yield response if block_given?
      response
    end
  end
end
