class SettingsController < ApplicationController
  def edit
    @setting = Setting.current
  end

  def update
    @setting = Setting.current
    attrs = setting_params
    # The password field renders blank for security; a blank submission must not wipe the
    # stored secret.
    attrs.delete(:smtp_password) if attrs[:smtp_password].blank?

    if @setting.update(attrs)
      redirect_to edit_settings_path, notice: "Settings were successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Sends a dummy alert through the configured channels synchronously so the result of each
  # channel can be reported back to the operator. Bypasses the state-change engine.
  def test_notification
    setting = Setting.current

    unless setting.any_channel_enabled?
      return redirect_to edit_settings_path,
        alert: "Enable and save at least one notification channel before sending a test."
    end

    results = NotificationDispatcher.new(setting).deliver(test_payload(setting))
    summary = results.map { |channel, outcome| "#{channel.to_s.capitalize}: #{format_outcome(outcome)}" }.join(" · ")

    if results.values.all? { |outcome| outcome == :ok }
      redirect_to edit_settings_path, notice: "Test notification — #{summary}"
    else
      redirect_to edit_settings_path, alert: "Test notification — #{summary}"
    end
  end

  private
    def setting_params
      params.expect(setting: [
        :probe_result_retention_days,
        :base_url,
        :slack_enabled, :slack_webhook_url,
        :email_enabled, :smtp_address, :smtp_port, :smtp_user_name, :smtp_password,
        :smtp_authentication, :smtp_starttls,
        :notification_from_email, :notification_recipient_email
      ])
    end

    def test_payload(setting)
      NotificationPayload.new(
        host_id: nil,
        host_name: "Test Target",
        group_name: "Diagnostic Tests",
        status: :down,
        event: :down,
        error_message: "Manual test notification triggered from Settings.",
        packet_loss: nil,
        latency: nil,
        status_code: nil,
        host_url: setting.absolute_url("/"),
        occurred_at: Time.current
      )
    end

    def format_outcome(outcome)
      outcome == :ok ? "sent" : "failed (#{outcome})"
    end
end
