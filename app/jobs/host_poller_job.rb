class HostPollerJob < ApplicationJob
  queue_as :default
  JITTER_MAX_SECONDS = 10

  def perform
    now = Time.current

    Host.find_each do |host|
      last_ping_at = host.pings.maximum(:recorded_at)

      # Enqueue if never pinged OR if the interval has elapsed since the last ping
      if last_ping_at.nil? || last_ping_at < now - host.interval.seconds
        jitter_seconds = rand(0.0..JITTER_MAX_SECONDS)
        PingJob.set(wait: jitter_seconds.seconds).perform_later(host.id)
      end
    end
  end
end
