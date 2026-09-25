class DeliverNotificationJob < ApplicationJob
  # Dedicated queue (and worker, see config/queue.yml) so alerts never wait behind probes.
  queue_as :notifications

  MAX_ATTEMPTS = 5

  # Each job delivers one NotificationDelivery (one channel), so retrying cannot duplicate
  # a message on another channel. Waits grow ~3s, 18s, 1.4m, 4.3m between attempts; after
  # the last one the delivery is marked failed and shows in the log and the warning banner.
  retry_on StandardError, attempts: MAX_ATTEMPTS, wait: :polynomially_longer do |job, error|
    job.mark_failed(error)
  end

  def perform(delivery_id)
    # Jobs enqueued before deliveries were tracked carry the payload hash itself.
    return deliver_untracked(delivery_id) if delivery_id.is_a?(Hash)

    delivery = NotificationDelivery.find_by(id: delivery_id)
    return if delivery.nil? || delivery.sent?

    dispatcher = NotificationDispatcher.new(Setting.current)
    unless dispatcher.channel_enabled?(delivery.channel)
      delivery.update!(status: :failed, error_message: "The #{delivery.channel} channel was disabled before delivery")
      return
    end

    delivery.increment!(:attempts)
    begin
      dispatcher.deliver_to!(delivery.channel, delivery.notification_payload)
    rescue => e
      delivery.update_columns(error_message: describe(e), updated_at: Time.current)
      raise
    end

    delivery.update!(status: :sent, delivered_at: Time.current, error_message: nil)
  end

  def mark_failed(error)
    delivery = NotificationDelivery.find_by(id: arguments.first)
    delivery&.update!(status: :failed, error_message: describe(error))
    Rails.logger.error("[Notifications] giving up on delivery ##{arguments.first} after #{MAX_ATTEMPTS} attempts: #{describe(error)}")
  end

  private

  def deliver_untracked(payload_args)
    NotificationDispatcher.deliver(NotificationPayload.from_job_args(payload_args))
  end

  def describe(error)
    "#{error.class}: #{error.message}".truncate(1000)
  end
end
