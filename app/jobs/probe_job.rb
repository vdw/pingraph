class ProbeJob < ApplicationJob
  queue_as :default

  # At most one probe per host is queued or running. If the queue falls behind, the extra
  # probes are dropped instead of piling up (Solid Queue concurrency controls).
  limits_concurrency key: ->(host_id) { host_id }, to: 1, duration: 1.minute, on_conflict: :discard

  # "database is locked" under SQLite write contention. The probe is simply run again; the
  # failed attempt's transaction was rolled back, so nothing is recorded twice.
  retry_on ActiveRecord::StatementTimeout, wait: 2.seconds, attempts: 3

  def perform(host_id)
    host = Host.find(host_id)
    return if stale?(host)

    ProbeService.execute(host)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ProbeJob] Host ##{host_id} not found, skipping."
  end

  private

  # A probe that waited in the queue for longer than its host's interval has been
  # overtaken by a newer slot. Running it late would only add load while the queue
  # is already behind.
  def stale?(host)
    return false if scheduled_at.nil?

    late_by = Time.current - scheduled_at
    if late_by > [ host.interval, 60 ].max.seconds
      Rails.logger.warn "[ProbeJob] Skipping probe for host ##{host.id}: #{late_by.round}s late."
      true
    else
      false
    end
  end
end
