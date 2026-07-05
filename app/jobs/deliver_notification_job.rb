class DeliverNotificationJob < ApplicationJob
  # Dedicated queue so a slow SMTP/Slack call during a mass outage cannot starve the probe
  # jobs sharing the default queue.
  queue_as :notifications

  # No retry: the dispatcher isolates and logs per-channel failures rather than raising, so
  # a retry would re-send to channels that already succeeded (duplicate alerts). Because
  # last_notified_status is advanced at decision time, a failed delivery is not re-alerted.
  # Misconfiguration is surfaced immediately by the synchronous "Send test" button instead.
  def perform(payload_args)
    payload = NotificationPayload.from_job_args(payload_args)
    NotificationDispatcher.deliver(payload)
  end
end
