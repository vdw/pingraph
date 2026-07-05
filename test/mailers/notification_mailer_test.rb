require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  test "alert targets the recipient and renders the event details" do
    setting = Setting.new(
      notification_from_email: "pingraph@example.com",
      notification_recipient_email: "ops@example.com",
      smtp_address: "smtp.example.com", smtp_port: 2525,
      smtp_authentication: "login", smtp_starttls: true
    )
    payload = NotificationPayload.new(
      host_id: 1, host_name: "Router", group_name: "LAN",
      status: :down, event: :down, error_message: "100% packet loss",
      packet_loss: 100, latency: nil, status_code: nil,
      host_url: "https://pg.test/hosts/1", occurred_at: Time.current
    )

    mail = NotificationMailer.with(payload: payload, setting: setting).alert

    assert_equal [ "ops@example.com" ], mail.to
    assert_equal [ "pingraph@example.com" ], mail.from
    assert_match "Router", mail.subject
    assert_match "DOWN", mail.subject
    assert_match "100% packet loss", mail.text_part.body.to_s
    assert_match "View host", mail.html_part.body.to_s
    assert_match "https://pg.test/hosts/1", mail.html_part.body.to_s
  end
end
