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
