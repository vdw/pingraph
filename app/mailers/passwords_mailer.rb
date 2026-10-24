class PasswordsMailer < ApplicationMailer
  # Sent through the SMTP server configured in Settings, like alerts (see NotificationMailer).
  def reset(user)
    @user = user
    mail subject: "Reset your password", to: user.email_address,
         delivery_method_options: Setting.current.smtp_delivery_options
  end
end
