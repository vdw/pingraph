require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  test "password reset uses the configured from address and base URL" do
    Setting.current.update_columns(notification_from_email: "alerts@home.test", base_url: "https://pingraph.home.test:8443")

    mail = PasswordsMailer.reset(users(:one))

    assert_equal [ "alerts@home.test" ], mail.from
    assert_includes mail.text_part.body.to_s, "https://pingraph.home.test:8443/passwords/"
  end

  test "falls back when nothing is configured" do
    Setting.current.update_columns(notification_from_email: nil, base_url: nil)

    mail = PasswordsMailer.reset(users(:one))

    assert_equal [ ApplicationMailer::FALLBACK_FROM ], mail.from
    assert_not_includes mail.from.first, "example.com"
  end
end
