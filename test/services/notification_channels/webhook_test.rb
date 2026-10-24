require "test_helper"

class NotificationChannels::WebhookTest < ActiveSupport::TestCase
  include HttpStubHelper

  test "posts the documented JSON body" do
    http = CapturingHttp.new
    setting = Setting.new(webhook_url: "http://n8n.lan:5678/webhook/pingraph?source=pg")
    occurred_at = Time.utc(2026, 10, 24, 12, 0, 0)

    with_stubbed_http(http) do
      assert_equal :ok, NotificationChannels::Webhook.new(setting).deliver(payload(occurred_at))
    end

    assert_equal "n8n.lan", http.host
    assert_equal "/webhook/pingraph?source=pg", http.last_request.path
    assert_equal "application/json", http.last_request["Content-Type"]
    assert_equal({
      "event" => "down",
      "status" => "down",
      "text" => "Router is DOWN",
      "host" => { "id" => 1, "name" => "Router", "group" => "LAN", "url" => "https://pg.test/hosts/1" },
      "error_message" => "HTTP 503",
      "packet_loss" => nil,
      "latency_ms" => 812.5,
      "status_code" => 503,
      "occurred_at" => "2026-10-24T12:00:00Z"
    }, http.json)
  end

  test "raises DeliveryError on a non-2xx response" do
    setting = Setting.new(webhook_url: "https://example.test/hook")

    with_stubbed_http(CapturingHttp.new(code: "404", body: "not found")) do
      error = assert_raises(NotificationChannels::Base::DeliveryError) do
        NotificationChannels::Webhook.new(setting).deliver(payload(Time.current))
      end
      assert_equal "example.test responded 404: not found", error.message
    end
  end

  private

  def payload(occurred_at)
    NotificationPayload.new(
      host_id: 1, host_name: "Router", group_name: "LAN", status: :down, event: :down,
      error_message: "HTTP 503", packet_loss: nil, latency: 812.5, status_code: 503,
      host_url: "https://pg.test/hosts/1", occurred_at: occurred_at
    )
  end
end
