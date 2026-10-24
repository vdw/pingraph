require "test_helper"

class NotificationChannels::TelegramTest < ActiveSupport::TestCase
  include HttpStubHelper

  setup do
    @setting = Setting.new(telegram_bot_token: "123456:ABC-def_1", telegram_chat_id: "-1001234")
  end

  test "sends an HTML message to the chat through the bot API" do
    http = CapturingHttp.new

    with_stubbed_http(http) do
      assert_equal :ok, NotificationChannels::Telegram.new(@setting).deliver(payload(:down, host_name: "R&D <router>"))
    end

    assert_equal "api.telegram.org", http.host
    assert http.use_ssl
    assert_equal "/bot123456:ABC-def_1/sendMessage", http.last_request.path

    body = http.json
    assert_equal "-1001234", body["chat_id"]
    assert_equal "HTML", body["parse_mode"]
    assert_includes body["text"], "🔴 <b>R&amp;D &lt;router&gt;</b> is DOWN"
    assert_includes body["text"], "Error: 100% packet loss"
    assert_includes body["text"], %(<a href="https://pg.test/hosts/1">View in Pingraph</a>)
  end

  test "a rejected message raises DeliveryError without the bot token" do
    http = CapturingHttp.new(code: "400", body: '{"ok":false,"description":"Bad Request: chat not found"}')

    error = with_stubbed_http(http) do
      assert_raises(NotificationChannels::Base::DeliveryError) do
        NotificationChannels::Telegram.new(@setting).deliver(payload(:down))
      end
    end

    assert_includes error.message, "chat not found"
    assert_not_includes error.message, "ABC-def_1"
  end

  private

  def payload(event, host_name: "Router")
    NotificationPayload.new(
      host_id: 1, host_name: host_name, group_name: "LAN",
      status: (event == :recovery ? :up : event), event: event,
      error_message: "100% packet loss", packet_loss: 100, latency: nil, status_code: nil,
      host_url: "https://pg.test/hosts/1", occurred_at: Time.current
    )
  end
end
