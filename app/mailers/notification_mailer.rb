class NotificationMailer < ApplicationMailer
  # SMTP is configured from the UI, so the connection settings are applied per-send via
  # delivery_method_options rather than the boot-time config.action_mailer.smtp_settings.
  def alert
    @payload = params[:payload]
    setting = params[:setting]

    mail(
      to: setting.notification_recipient_email,
      from: setting.notification_from_email,
      subject: "[Pingraph] #{@payload.host_name} #{@payload.headline}",
      delivery_method_options: setting.smtp_delivery_options
    )
  end
end
