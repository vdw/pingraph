module StatusPage
  class ResultStateCalculator
    Entry = Struct.new(:result, :state, :hard_failure, keyword_init: true)

    def self.entries_for_host(host, start_at:, end_at:)
      lookback_count = [ ProbeService::FAILURE_THRESHOLD - 1, 0 ].max
      prior_results = if lookback_count.positive?
        host.probe_results.where("recorded_at < ?", start_at).order(recorded_at: :desc).limit(lookback_count).to_a.reverse
      else
        []
      end

      results = host.probe_results.where(recorded_at: start_at...end_at).order(recorded_at: :asc)
      consecutive_failures = trailing_failures(prior_results)

      results.map do |result|
        consecutive_failures = result.success? ? 0 : consecutive_failures + 1
        hard_failure = consecutive_failures >= ProbeService::FAILURE_THRESHOLD
        Entry.new(
          result: result,
          hard_failure: hard_failure,
          state: state_for(host, result, hard_failure)
        )
      end
    end

    def self.latest_state(host)
      latest_result = host.latest_probe_result
      return :unknown if latest_result.nil?

      entries = entries_for_host(host, start_at: 24.hours.ago, end_at: Time.current)
      entries.last&.state || fallback_state(host, latest_result)
    end

    def self.state_for(host, result, hard_failure = false)
      return :down if hard_failure
      return :degraded if degraded?(host, result)
      return :operational if result.success?

      :degraded
    end

    def self.degraded?(host, result)
      host.result_degraded?(result)
    end

    def self.trailing_failures(results)
      results.reverse.take_while { |result| !result.success? }.size
    end
    private_class_method :trailing_failures

    def self.fallback_state(host, result)
      return :down unless result.success?
      return :degraded if degraded?(host, result)

      :operational
    end
    private_class_method :fallback_state
  end
end
