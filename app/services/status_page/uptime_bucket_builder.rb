module StatusPage
  class UptimeBucketBuilder
    DEFAULT_BUCKET_COUNT = 48
    WINDOW = 24.hours

    def self.for_host(host, end_at: Time.current, bucket_count: DEFAULT_BUCKET_COUNT)
      start_at = end_at - WINDOW
      bucket_duration = WINDOW / bucket_count
      entries = ResultStateCalculator.entries_for_host(host, start_at: start_at, end_at: end_at)
      buckets = Array.new(bucket_count) { |index| empty_bucket(start_at, bucket_duration, index) }
      max_gap = max_sample_gap(host)

      entries.each_with_index do |entry, position|
        index = [ ((entry.result.recorded_at - start_at) / bucket_duration).floor, bucket_count - 1 ].min
        next if index.negative?

        # Each sample stands for the time until the next one, capped so that a period when
        # Pingraph itself was not running counts as unmonitored instead of as uptime.
        next_at = entries[position + 1]&.result&.recorded_at || end_at
        seconds = (next_at - entry.result.recorded_at).clamp(0, max_gap)

        buckets[index][:entries] << entry
        buckets[index][:monitored_seconds] += seconds
        buckets[index][:healthy_seconds] += seconds if entry.result.success?
      end

      buckets.map { |bucket| finalize_bucket(bucket, host) }
    end

    # Longest gap one sample may cover: two intervals, and never less than interval + 60s
    # (the poller's granularity plus jitter).
    def self.max_sample_gap(host)
      [ host.interval * 2, host.interval + 60 ].max.to_f
    end

    def self.combine(host_blocks)
      return [] if host_blocks.empty?

      host_blocks.first.each_index.map do |index|
        states = host_blocks.filter_map { |blocks| blocks[index]&.fetch(:state, nil) }
        {
          start_at: host_blocks.first[index][:start_at],
          end_at: host_blocks.first[index][:end_at],
          state: overall_state(states)
        }
      end
    end

    # Share of monitored time the host was up. Time Pingraph was not monitoring is left
    # out (see coverage) rather than silently counted as up.
    def self.percentage(blocks)
      total = blocks.sum { |b| b[:monitored_seconds].to_f }
      return nil if total.zero?

      healthy = blocks.sum { |b| b[:healthy_seconds].to_f }
      (healthy / total * 100).floor(1)
    end

    # Share of the window that was actually monitored (0.0..1.0).
    def self.coverage(blocks)
      return 0.0 if blocks.empty?

      window = blocks.sum { |b| (b[:end_at] - b[:start_at]).to_f }
      return 0.0 if window.zero?

      (blocks.sum { |b| b[:monitored_seconds].to_f } / window).clamp(0.0, 1.0)
    end

    def self.overall_state(states)
      return :down if states.include?(:down)
      return :degraded if states.include?(:degraded)
      return :operational if states.include?(:operational)

      :no_data
    end

    def self.empty_bucket(start_at, bucket_duration, index)
      {
        start_at: start_at + (bucket_duration * index),
        end_at: start_at + (bucket_duration * (index + 1)),
        entries: [],
        monitored_seconds: 0.0,
        healthy_seconds: 0.0
      }
    end
    private_class_method :empty_bucket

    def self.finalize_bucket(bucket, host)
      entries = bucket[:entries]
      state = if entries.empty?
        :no_data
      elsif entries.any? { |entry| entry.state == :down }
        :down
      elsif entries.any? { |entry| entry.state == :degraded }
        :degraded
      else
        :operational
      end

      successful_latencies = entries.filter_map do |entry|
        next unless entry.result.success? && entry.result.latency.present?

        entry.result.latency.to_f
      end

      bucket.except(:entries).merge(
        state: state,
        average_latency: successful_latencies.any? ? (successful_latencies.sum / successful_latencies.size).round(2) : nil,
        sample_count: entries.size,
        healthy_count: entries.count { |entry| entry.result.success? },
        degraded_threshold_ms: host.latency_threshold_ms
      )
    end
    private_class_method :finalize_bucket
  end
end
