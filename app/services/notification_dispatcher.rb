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
    enabled_channels.index_with { |name| safe_deliver(name, payload) }
  end

  def enabled_channels
    CHANNELS.keys.select { |name| channel_enabled?(name) }
  end

  def channel_enabled?(name)
    CHANNELS.key?(name.to_sym) && setting.public_send("#{name}_enabled?")
  end

  # Delivers to a single channel and raises on failure (used by DeliverNotificationJob,
  # which retries per channel).
  def deliver_to!(name, payload)
    CHANNELS.fetch(name.to_sym).call(setting).deliver(payload)
  end

  private

  attr_reader :setting

  def safe_deliver(name, payload)
    deliver_to!(name, payload)
  rescue => e
    Rails.logger.error("[Notifications] #{name} delivery failed: #{e.class}: #{e.message}")
    e.message
  end
end
