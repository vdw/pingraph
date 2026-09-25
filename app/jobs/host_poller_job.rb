# Runs every minute (config/recurring.yml) and schedules each host's probes for the coming
# minute on exact slots: next_probe_at, next_probe_at + interval, ... This keeps the real
# gap between checks equal to the configured interval, including intervals under 60s.
class HostPollerJob < ApplicationJob
  queue_as :default
  JITTER_MAX_SECONDS = 10
  # Must match the recurring schedule ("every minute").
  POLL_PERIOD = 60.seconds

  def perform
    now = Time.current
    window_end = now + POLL_PERIOD

    Host.where(next_probe_at: nil).or(Host.where(next_probe_at: ...window_end)).find_each do |host|
      schedule(host, now, window_end)
    end
  end

  private

  def schedule(host, now, window_end)
    interval = host.interval.seconds
    slot = host.next_probe_at

    # New host, changed interval, or Pingraph was stopped for a while: start fresh rather
    # than firing a burst of missed probes. The jitter spreads hosts across the minute.
    slot = now + rand(0.0..JITTER_MAX_SECONDS).seconds if slot.nil? || slot < now - interval

    while slot < window_end
      ProbeJob.set(wait_until: slot).perform_later(host.id)
      slot += interval
    end

    host.update_column(:next_probe_at, slot)
  end
end
