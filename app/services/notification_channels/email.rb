module NotificationChannels
  class Email < Base
    # Delivered synchronously with deliver_now: we are already inside the async
    # DeliverNotificationJob, and the SMTP options are applied per-send. deliver_later
    # would enqueue a second job on the mailers queue and escape our :notifications queue.
    def deliver(payload)
      NotificationMailer.with(payload: payload, setting: setting).alert.deliver_now
      :ok
    end
  end
end
