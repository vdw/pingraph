require "test_helper"

class NotificationDispatcherTest < ActiveSupport::TestCase
  def build_payload
    NotificationPayload.new(
      host_id: 1, host_name: "Router", group_name: "LAN",
      status: :down, event: :down, error_message: "100% packet loss",
      packet_loss: 100, latency: nil, status_code: nil,
      host_url: "https://pg.test/hosts/1", occurred_at: Time.current
    )
  end

  test "delivers to no channels when none are enabled" do
    setting = Setting.new(slack_enabled: false, email_enabled: false)
    assert_empty NotificationDispatcher.new(setting).deliver(build_payload)
  end

  test "isolates a failing channel and reports per-channel outcomes" do
    setting = Setting.new(
      slack_enabled: true, slack_webhook_url: "https://hooks.slack.com/services/x",
      email_enabled: true, smtp_address: "smtp.test", smtp_port: 587,
      notification_from_email: "from@test.dev", notification_recipient_email: "to@test.dev",
      base_url: "https://pg.test"
    )
    ActionMailer::Base.deliveries.clear

    with_stubbed_http(FakeSlackHttp.new(success: false)) do
      results = NotificationDispatcher.new(setting).deliver(build_payload)

      assert_equal :ok, results[:email], "email should succeed independently of Slack"
      assert_kind_of String, results[:slack], "failing Slack should be captured as a message"
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "returns :ok for a successful Slack delivery" do
    setting = Setting.new(slack_enabled: true, slack_webhook_url: "https://hooks.slack.com/services/x")

    with_stubbed_http(FakeSlackHttp.new(success: true)) do
      assert_equal({ slack: :ok }, NotificationDispatcher.new(setting).deliver(build_payload))
    end
  end

  private

  def with_stubbed_http(fake)
    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) { |_host, _port| fake }
    yield
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end

  class FakeSlackHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def initialize(success:)
      @success = success
    end

    def request(_request)
      klass = @success ? Net::HTTPOK : Net::HTTPInternalServerError
      response = klass.new("1.1", @success ? "200" : "500", "stub")
      def response.body = "stub body"
      response
    end
  end
end
