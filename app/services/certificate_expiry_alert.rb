# Records the certificate expiry seen by an HTTPS check and decides whether to warn about it.
# Each certificate (identified by its expiry time) is reported once, when it first falls
# within the host's ssl_expiry_warn_days; a renewed certificate gets its own warning.
#
# Called inside the probe-persist transaction, like AlertEvaluator. Returns a
# NotificationPayload, or nil.
class CertificateExpiryAlert
  def self.evaluate(host, result, status)
    expires_at = result.certificate_expires_at
    return nil if expires_at.nil?

    changes = {}
    changes[:ssl_expires_at] = expires_at unless host.ssl_expires_at == expires_at

    due = host.notifications_enabled? && host.ssl_expiry_warn_days.present? &&
      expires_at <= result.recorded_at + host.ssl_expiry_warn_days.days &&
      host.ssl_expiry_notified_for != expires_at
    changes[:ssl_expiry_notified_for] = expires_at if due

    host.update_columns(changes) if changes.any?
    return nil unless due

    NotificationPayload.new(
      host_id: host.id,
      host_name: host.name,
      group_name: host.group.name,
      status: status.to_sym,
      event: :cert_expiring,
      error_message: nil,
      packet_loss: nil,
      latency: nil,
      status_code: nil,
      host_url: Setting.current.absolute_url("/hosts/#{host.id}"),
      occurred_at: result.recorded_at,
      certificate_expires_at: expires_at
    )
  end
end
