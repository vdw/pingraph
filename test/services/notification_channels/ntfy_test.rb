require "test_helper"

class NotificationChannels::NtfyTest < ActiveSupport::TestCase
  include HttpStubHelper

  test "publishes JSON to the server root with the topic, priority, tag and link" do
    http = CapturingHttp.new
    setting = Setting.new(ntfy_url: "https://ntfy.sh/pingraph-alerts")

    with_stubbed_http(http) do
      assert_equal :ok, NotificationChannels::Ntfy.new(setting).deliver(payload(:down))
    end

    assert_equal "ntfy.sh", http.host
    assert_equal "/", http.last_request.path
    assert_nil http.last_request["Authorization"]

    body = http.json
    assert_equal "pingraph-alerts", body["topic"]
    assert_equal "Router is DOWN", body["title"]
    assert_includes body["message"], "Error: 100% packet loss"
    assert_equal 4, body["priority"]
    assert_equal [ "red_circle" ], body["tags"]
    assert_equal "https://pg.test/hosts/1", body["click"]
  end

  test "a self-hosted server under a path, with an access token" do
    http = CapturingHttp.new
    setting = Setting.new(ntfy_url: "http://nas.lan:8080/ntfy/alerts/", ntfy_token: "tk_secret")

    with_stubbed_http(http) { NotificationChannels::Ntfy.new(setting).deliver(payload(:recovery)) }

    assert_equal 8080, http.port
    assert_not http.use_ssl
    assert_equal "/ntfy/", http.last_request.path
    assert_equal "Bearer tk_secret", http.last_request["Authorization"]
    assert_equal "alerts", http.json["topic"]
    assert_equal 3, http.json["priority"]
    assert_equal [ "green_circle" ], http.json["tags"]
  end

  test "raises DeliveryError on a non-2xx response" do
    setting = Setting.new(ntfy_url: "https://ntfy.sh/pingraph-alerts")

    with_stubbed_http(CapturingHttp.new(code: "403", body: "forbidden")) do
      assert_raises(NotificationChannels::Base::DeliveryError) do
        NotificationChannels::Ntfy.new(setting).deliver(payload(:down))
      end
    end
  end

  private

  def payload(event)
    NotificationPayload.new(
      host_id: 1, host_name: "Router", group_name: "LAN",
      status: (event == :recovery ? :up : event), event: event,
      error_message: "100% packet loss", packet_loss: 100, latency: nil, status_code: nil,
      host_url: "https://pg.test/hosts/1", occurred_at: Time.current
    )
  end
end
