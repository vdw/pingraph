require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "validates probe result retention options" do
    setting = Setting.new(probe_result_retention_days: 45)

    assert_not setting.valid?
    assert_includes setting.errors[:probe_result_retention_days], "is not included in the list"
  end

  test "slack channel requires an https webhook and a base url" do
    setting = Setting.new(probe_result_retention_days: 90, slack_enabled: true)

    assert_not setting.valid?
    assert_includes setting.errors[:slack_webhook_url], "can't be blank"
    assert_includes setting.errors[:base_url], "can't be blank"

    setting.slack_webhook_url = "http://insecure.example"
    setting.base_url = "https://pg.test"
    assert_not setting.valid?
    assert_includes setting.errors[:slack_webhook_url], "must be a valid https:// URL"

    setting.slack_webhook_url = "https://hooks.slack.com/services/x"
    assert setting.valid?, setting.errors.full_messages.to_sentence
  end

  test "email channel requires smtp address, from, recipient and valid emails" do
    setting = Setting.new(probe_result_retention_days: 90, email_enabled: true, base_url: "https://pg.test")

    assert_not setting.valid?
    assert_includes setting.errors[:smtp_address], "can't be blank"
    assert_includes setting.errors[:notification_from_email], "can't be blank"
    assert_includes setting.errors[:notification_recipient_email], "can't be blank"

    setting.smtp_address = "smtp.example.com"
    setting.notification_from_email = "not-an-email"
    setting.notification_recipient_email = "ops@example.com"
    assert_not setting.valid?
    assert_includes setting.errors[:notification_from_email], "must be a valid email address"

    setting.notification_from_email = "pingraph@example.com"
    assert setting.valid?, setting.errors.full_messages.to_sentence
  end

  test "telegram channel requires a bot token and chat id in the right format" do
    setting = Setting.new(probe_result_retention_days: 90, base_url: "https://pg.test", telegram_enabled: true)

    assert_not setting.valid?
    assert_includes setting.errors[:telegram_bot_token], "can't be blank"
    assert_includes setting.errors[:telegram_chat_id], "can't be blank"

    setting.telegram_bot_token = "not a token/../x"
    setting.telegram_chat_id = "my chat"
    assert_not setting.valid?
    assert setting.errors[:telegram_bot_token].any?
    assert setting.errors[:telegram_chat_id].any?

    setting.telegram_bot_token = " 123456789:AAH-x_y \n"
    setting.telegram_chat_id = "-1001234567890"
    assert setting.valid?, setting.errors.full_messages.to_sentence
    assert_equal "123456789:AAH-x_y", setting.telegram_bot_token

    setting.telegram_chat_id = "@pingraph_alerts"
    assert setting.valid?, setting.errors.full_messages.to_sentence
  end

  test "ntfy channel requires a server URL ending in a topic" do
    setting = Setting.new(probe_result_retention_days: 90, base_url: "https://pg.test", ntfy_enabled: true)

    assert_not setting.valid?
    assert_includes setting.errors[:ntfy_url], "can't be blank"

    [ "https://ntfy.sh", "https://ntfy.sh/", "ftp://ntfy.sh/alerts", "https://ntfy.sh/bad topic", "https://ntfy.sh/alerts?x=1" ].each do |url|
      setting.ntfy_url = url
      assert_not setting.valid?, "#{url} should be rejected"
    end

    [ "https://ntfy.sh/pingraph-alerts", "http://nas.lan:8080/ntfy/alerts/" ].each do |url|
      setting.ntfy_url = url
      assert setting.valid?, "#{url}: #{setting.errors.full_messages.to_sentence}"
    end
  end

  test "webhook channel requires an http(s) URL" do
    setting = Setting.new(probe_result_retention_days: 90, base_url: "https://pg.test", webhook_enabled: true)

    assert_not setting.valid?
    assert_includes setting.errors[:webhook_url], "can't be blank"

    setting.webhook_url = "javascript:alert(1)"
    assert_not setting.valid?
    assert_includes setting.errors[:webhook_url], "must be a valid http(s):// URL"

    setting.webhook_url = "http://homeassistant.local:8123/api/webhook/abc"
    assert setting.valid?, setting.errors.full_messages.to_sentence
  end

  test "any_channel_enabled? covers every channel" do
    assert_not Setting.new.any_channel_enabled?

    NotificationDispatcher::CHANNELS.each_key do |name|
      assert Setting.new("#{name}_enabled" => true).any_channel_enabled?, name
    end
  end

  test "new channel secrets are encrypted at rest" do
    setting = Setting.create!(
      probe_result_retention_days: 90, base_url: "https://pg.test",
      telegram_enabled: true, telegram_bot_token: "123456:SECRET", telegram_chat_id: "42",
      ntfy_enabled: true, ntfy_url: "https://ntfy.sh/secret-topic", ntfy_token: "tk_secret",
      webhook_enabled: true, webhook_url: "https://example.test/hook/secret"
    )

    %w[telegram_bot_token ntfy_url ntfy_token webhook_url].each do |column|
      raw = Setting.connection.select_value("SELECT #{column} FROM settings WHERE id = #{setting.id}")
      assert_not_includes raw, "secret", column
      assert_not_includes raw, "SECRET", column
    end
    assert_equal "tk_secret", setting.reload.ntfy_token
  end

  test "secrets are encrypted at rest" do
    setting = Setting.create!(
      probe_result_retention_days: 90, slack_enabled: true, base_url: "https://pg.test",
      slack_webhook_url: "https://hooks.slack.com/services/SECRET"
    )

    raw = Setting.connection.select_value("SELECT slack_webhook_url FROM settings WHERE id = #{setting.id}")
    assert_not_equal "https://hooks.slack.com/services/SECRET", raw
    assert_equal "https://hooks.slack.com/services/SECRET", setting.reload.slack_webhook_url
  end

  test "smtp_delivery_options omits blank credentials" do
    setting = Setting.new(smtp_address: "smtp.example.com", smtp_port: 587, smtp_authentication: "plain", smtp_starttls: true)
    options = setting.smtp_delivery_options

    assert_equal "smtp.example.com", options[:address]
    assert_equal 587, options[:port]
    assert_equal :plain, options[:authentication]
    assert_not options.key?(:user_name)
    assert_not options.key?(:password)
  end

  test "absolute_url builds links from base_url and is nil without one" do
    assert_nil Setting.new.absolute_url("/hosts/1")
    assert_equal "https://pg.test/hosts/1", Setting.new(base_url: "https://pg.test/").absolute_url("/hosts/1")
  end
end
