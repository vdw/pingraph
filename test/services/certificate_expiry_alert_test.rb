require "test_helper"

class CertificateExpiryAlertTest < ActiveSupport::TestCase
  setup do
    @host = Host.create!(group: groups(:one), name: "Web", probe_type: :http, address: "https://web.test", interval: 60)
    Setting.current.update_columns(slack_enabled: true, slack_webhook_url: "https://hooks.slack.com/services/x", base_url: "https://pg.test")
  end

  test "warns once per certificate when it enters the warning window" do
    expires_at = (10.days + 1.hour).from_now.change(usec: 0)

    assert_difference("NotificationDelivery.count", 1) { persist(ok_result(expires_at)) }

    delivery = NotificationDelivery.last
    assert_equal "cert_expiring", delivery.event
    payload = delivery.notification_payload
    assert_equal expires_at, payload.certificate_expires_at
    assert_equal "certificate EXPIRES in 10 days", payload.headline

    @host.reload
    assert_equal expires_at, @host.ssl_expires_at
    assert_equal expires_at, @host.ssl_expiry_notified_for

    # The same certificate on the next check: no new warning.
    assert_no_difference("NotificationDelivery.count") { persist(ok_result(expires_at)) }
  end

  test "a certificate outside the window is only recorded; a renewed one that is close warns again" do
    far = 60.days.from_now.change(usec: 0)
    assert_no_difference("NotificationDelivery.count") { persist(ok_result(far)) }
    assert_equal far, @host.reload.ssl_expires_at
    assert_nil @host.ssl_expiry_notified_for

    @host.update_columns(ssl_expiry_notified_for: 5.days.from_now.change(usec: 0))
    near = 3.days.from_now.change(usec: 0)
    assert_difference("NotificationDelivery.count", 1) { persist(ok_result(near)) }
  end

  test "no warning when expiry warnings or notifications are off" do
    expires_at = 2.days.from_now.change(usec: 0)

    @host.update!(ssl_expiry_warn_days: nil)
    assert_no_difference("NotificationDelivery.count") { persist(ok_result(expires_at)) }

    @host.update!(ssl_expiry_warn_days: 14, notifications_enabled: false)
    assert_no_difference("NotificationDelivery.count") { persist(ok_result(expires_at)) }
    assert_equal expires_at, @host.reload.ssl_expires_at
  end

  test "headline for expired and same-day certificates" do
    now = Time.current
    assert_equal "certificate has EXPIRED", payload(now, now - 1.hour).headline
    assert_equal "certificate EXPIRES TODAY", payload(now, now + 2.hours).headline
    assert_equal "certificate EXPIRES in 1 day", payload(now, now + 1.day + 1.hour).headline
  end

  private

  def persist(result)
    ProbeService.send(:persist_result!, @host.reload, result)
  end

  def ok_result(expires_at)
    ProbeService::Result.new(probe_type: :http, success: true, latency: 20.0, status_code: 200, metadata: {},
      recorded_at: Time.current, certificate_expires_at: expires_at)
  end

  def payload(occurred_at, expires_at)
    NotificationPayload.new(host_id: 1, host_name: "Web", group_name: "LAN", status: :up, event: :cert_expiring,
      error_message: nil, packet_loss: nil, latency: nil, status_code: nil, host_url: nil,
      occurred_at: occurred_at, certificate_expires_at: expires_at)
  end
end
