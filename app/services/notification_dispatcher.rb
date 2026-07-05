# Reads the enabled channels off a Setting, delivers the payload to each, and returns a
# per-channel result map (e.g. { slack: :ok, email: "Net::SMTPAuthenticationError ..." }).
# Each channel is isolated so a misconfigured relay cannot block another channel — this
# powers both async delivery and the synchronous "Send test notification" button.
class NotificationDispatcher
  CHANNELS = {
    slack: ->(setting) { NotificationChannels::Slack.new(setting) },
    email: ->(setting) { NotificationChannels::Email.new(setting) }
  }.freeze

  def self.deliver(payload, setting: Setting.current)
    new(setting).deliver(payload)
  end

  def initialize(setting)
    @setting = setting
  end

  def deliver(payload)
    results = {}
    results[:slack] = safe_deliver(:slack, payload) if setting.slack_enabled?
    results[:email] = safe_deliver(:email, payload) if setting.email_enabled?
    results
  end

  private

  attr_reader :setting

  def safe_deliver(name, payload)
    CHANNELS.fetch(name).call(setting).deliver(payload)
  rescue => e
    Rails.logger.error("[Notifications] #{name} delivery failed: #{e.class}: #{e.message}")
    e.message
  end
end
