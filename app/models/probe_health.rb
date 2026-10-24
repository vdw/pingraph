# Answers "is Pingraph actually checking hosts?" for the layout banners, the Stale badges and
# GET /health. A monitor that silently stops would otherwise keep showing its last statuses.
module ProbeHealth
  # HostPollerJob runs every minute, so three missed runs means the worker isn't running.
  STALL_AFTER = 3.minutes
  # A probe that starts this long after its slot (or is skipped as stale) counts as late.
  LATE_AFTER = 30.seconds
  # Falling behind: at least LATE_MINIMUM late probes, making up LATE_RATIO of all probes,
  # over the current and previous clock hour. The ratio keeps the burst of late probes after
  # a restart from counting; the minimum keeps a few hosts' blips from counting.
  LATE_MINIMUM = 10
  LATE_RATIO = 0.2
  COUNTER_TTL = 3.hours

  def self.last_poll_at
    Setting.current.poller_heartbeat_at
  end

  def self.record_poll!(at = Time.current)
    Setting.current.update_column(:poller_heartbeat_at, at)
  end

  # True when there are hosts to check but the poller hasn't run recently (or ever).
  def self.stalled?(now = Time.current)
    return false unless Host.exists?

    heartbeat = last_poll_at
    heartbeat.nil? || heartbeat < now - STALL_AFTER
  end

  # Called by ProbeJob for every probe it runs or skips.
  def self.record_probe!(late:, at: Time.current)
    Rails.cache.increment(counter_key(:total, at), 1, expires_in: COUNTER_TTL)
    Rails.cache.increment(counter_key(:late, at), 1, expires_in: COUNTER_TTL) if late
  end

  def self.probe_counts(now = Time.current)
    hours = [ now, now - 1.hour ]
    {
      late: hours.sum { |at| Rails.cache.read_counter(counter_key(:late, at)).to_i },
      total: hours.sum { |at| Rails.cache.read_counter(counter_key(:total, at)).to_i }
    }
  end

  # True when probes regularly start late: the worker has too few threads for the hosts.
  def self.falling_behind?(now = Time.current)
    counts = probe_counts(now)
    counts[:late] >= LATE_MINIMUM && counts[:late] >= counts[:total] * LATE_RATIO
  end

  def self.counter_key(kind, at)
    "probe_health/#{kind}/#{at.utc.strftime('%Y%m%d%H')}"
  end
  private_class_method :counter_key
end
