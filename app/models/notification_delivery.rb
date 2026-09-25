# One alert sent to one channel. Each row is delivered (and retried) by its own
# DeliverNotificationJob, so a Slack outage never re-sends an email that already went out,
# and every attempt stays visible in the notification log.
class NotificationDelivery < ApplicationRecord
  belongs_to :host, optional: true

  enum :status, { pending: 0, sent: 1, failed: 2 }, default: :pending

  serialize :payload, coder: JSON

  validates :channel, inclusion: { in: NotificationDispatcher::CHANNELS.keys.map(&:to_s) }
  validates :event, :payload, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :finished, -> { where(status: [ statuses[:sent], statuses[:failed] ]) }

  # Creates one pending delivery per channel enabled right now.
  def self.create_for!(payload, setting: Setting.current)
    NotificationDispatcher.new(setting).enabled_channels.map do |channel|
      create!(host_id: payload.host_id, channel: channel.to_s, event: payload.event.to_s, payload: payload.to_job_args)
    end
  end

  # The most recent delivery that reached a final state, when it failed. Drives the
  # "alerts are not being delivered" banner; a later successful delivery clears it.
  def self.latest_failure
    latest = finished.recent.first
    latest if latest&.failed?
  end

  def notification_payload
    NotificationPayload.from_job_args(payload)
  end

  def host_name
    payload["host_name"].presence || host&.name
  end

  def retry!
    update!(status: :pending, error_message: nil)
    DeliverNotificationJob.perform_later(id)
  end
end
