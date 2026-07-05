require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    Setting.delete_all
  end

  test "should get edit" do
    get edit_settings_url

    assert_response :success
    assert_equal 90, Setting.current.probe_result_retention_days
  end

  test "should update setting" do
    patch settings_url, params: { setting: { probe_result_retention_days: 60 } }

    assert_redirected_to edit_settings_url
    assert_equal 60, Setting.current.probe_result_retention_days
  end

  test "should reject invalid retention days" do
    patch settings_url, params: { setting: { probe_result_retention_days: 45 } }

    assert_response :unprocessable_entity
    assert_equal 90, Setting.current.probe_result_retention_days
  end

  test "updates notification channel settings" do
    patch settings_url, params: { setting: {
      probe_result_retention_days: 90, base_url: "https://pg.test",
      slack_enabled: true, slack_webhook_url: "https://hooks.slack.com/services/x"
    } }

    assert_redirected_to edit_settings_url
    setting = Setting.current
    assert setting.slack_enabled?
    assert_equal "https://hooks.slack.com/services/x", setting.slack_webhook_url
  end

  test "rejects enabling slack without a webhook" do
    patch settings_url, params: { setting: { probe_result_retention_days: 90, slack_enabled: true, base_url: "https://pg.test" } }

    assert_response :unprocessable_entity
    assert_not Setting.current.slack_enabled?
  end

  test "a blank smtp password does not overwrite the stored secret" do
    Setting.current.update!(
      probe_result_retention_days: 90, email_enabled: true, base_url: "https://pg.test",
      smtp_address: "smtp.example.com", smtp_port: 587,
      notification_from_email: "from@example.com", notification_recipient_email: "to@example.com",
      smtp_password: "s3cret"
    )

    patch settings_url, params: { setting: {
      probe_result_retention_days: 90, email_enabled: true, base_url: "https://pg.test",
      smtp_address: "smtp.example.com", smtp_port: 587,
      notification_from_email: "from@example.com", notification_recipient_email: "to@example.com",
      smtp_password: ""
    } }

    assert_redirected_to edit_settings_url
    assert_equal "s3cret", Setting.current.smtp_password
  end

  test "test_notification requires an enabled channel" do
    post test_notification_settings_url

    assert_redirected_to edit_settings_url
    assert_match(/enable and save/i, flash[:alert])
  end

  test "test_notification reports the per-channel outcome" do
    Setting.current.update!(
      probe_result_retention_days: 90, base_url: "https://pg.test",
      slack_enabled: true, slack_webhook_url: "https://hooks.slack.com/services/x"
    )
    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) { |_host, _port| StubOkHttp.new }

    post test_notification_settings_url

    assert_redirected_to edit_settings_url
    assert_match(/Slack: sent/, flash[:notice])
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end

  class StubOkHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(_request)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      def response.body = "ok"
      response
    end
  end
end
