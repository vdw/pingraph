module StatusPage
  class UptimeBucketBuilder
    DEFAULT_BUCKET_COUNT = 48
    WINDOW = 24.hours

    def self.for_host(host, end_at: Time.current, bucket_count: DEFAULT_BUCKET_COUNT)
      start_at = end_at - WINDOW
      bucket_duration = WINDOW / bucket_count
      entries = ResultStateCalculator.entries_for_host(host, start_at: start_at, end_at: end_at)
      buckets = Array.new(bucket_count) { |index| empty_bucket(start_at, bucket_duration, index) }

      entries.each do |entry|
        index = [ ((entry.result.recorded_at - start_at) / bucket_duration).floor, bucket_count - 1 ].min
        next if index.negative?

        buckets[index][:entries] << entry
      end

      buckets.map { |bucket| finalize_bucket(bucket, host) }
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

    def self.percentage(blocks)
      total = blocks.sum { |b| b[:sample_count] }
      return nil if total.zero?

      healthy = blocks.sum { |b| b[:healthy_count] }
      (healthy.to_f / total * 100).round(1)
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
        entries: []
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

      bucket.merge(
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
