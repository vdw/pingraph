require "test_helper"

class NotificationChannels::SlackTest < ActiveSupport::TestCase
  test "posts a colour-coded mrkdwn payload and returns :ok" do
    setting = Setting.new(slack_webhook_url: "https://hooks.slack.com/services/T/B/x")
    http = CapturingHttp.new(success: true)

    with_stubbed_http(http) do
      assert_equal :ok, NotificationChannels::Slack.new(setting).deliver(payload(:down))
    end

    body = JSON.parse(http.body)
    assert_includes body["text"], "Router"
    assert_includes body["text"], "DOWN"
    assert_includes body["text"], "View in Pingraph"

    attachment = body["attachments"].first
    assert_equal "#dc2626", attachment["color"]
    assert(attachment["fields"].any? { |field| field["title"] == "Packet loss" })
  end

  test "uses the recovery colour for recovery events" do
    setting = Setting.new(slack_webhook_url: "https://hooks.slack.com/services/T/B/x")
    http = CapturingHttp.new(success: true)

    with_stubbed_http(http) { NotificationChannels::Slack.new(setting).deliver(payload(:recovery)) }

    assert_equal "#16a34a", JSON.parse(http.body)["attachments"].first["color"]
  end

  test "raises DeliveryError on a non-2xx response" do
    setting = Setting.new(slack_webhook_url: "https://hooks.slack.com/services/T/B/x")

    with_stubbed_http(CapturingHttp.new(success: false)) do
      assert_raises(NotificationChannels::Base::DeliveryError) do
        NotificationChannels::Slack.new(setting).deliver(payload(:down))
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

  def with_stubbed_http(fake)
    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) { |_host, _port| fake }
    yield
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end

  class CapturingHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout
    attr_reader :body

    def initialize(success:)
      @success = success
    end

    def request(request)
      @body = request.body
      klass = @success ? Net::HTTPOK : Net::HTTPInternalServerError
      response = klass.new("1.1", @success ? "200" : "500", "stub")
      def response.body = "stub body"
      response
    end
  end
end
