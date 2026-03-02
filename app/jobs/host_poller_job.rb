class HostPollerJob < ApplicationJob
  queue_as :default

  def perform
    Host.find_each do |host|
      last_ping_at = host.pings.maximum(:recorded_at)

      # Enqueue if never pinged OR if the interval has elapsed since the last ping
      if last_ping_at.nil? || last_ping_at < Time.current - host.interval.seconds
        PingJob.perform_later(host.id)
      end
    end
  end
end
