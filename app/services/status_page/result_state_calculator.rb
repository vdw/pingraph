module StatusPage
  # Replays a host's probe results with the same rules ProbeService uses for the live
  # status: Down after FAILURE_THRESHOLD failures in a row, Degraded after
  # Host::DEGRADED_THRESHOLD problem samples in a row, and a single blip changes nothing.
  class ResultStateCalculator
    # problem: this sample on its own was failed, slow or lossy.
    Entry = Struct.new(:result, :state, :hard_failure, :problem, keyword_init: true)

    def self.entries_for_host(host, start_at:, end_at:)
      lookback_count = [ ProbeService::FAILURE_THRESHOLD, Host::DEGRADED_THRESHOLD ].max - 1
      prior_results = if lookback_count.positive?
        host.probe_results.where("recorded_at < ?", start_at).order(recorded_at: :desc).limit(lookback_count).to_a.reverse
      else
        []
      end

      results = host.probe_results.where(recorded_at: start_at...end_at).order(recorded_at: :asc)
      consecutive_failures = trailing_count(prior_results) { |result| !result.success? }
      consecutive_issues = trailing_count(prior_results) { |result| host.result_degraded?(result) }
      previous_state = :operational

      results.map do |result|
        problem = host.result_degraded?(result)
        consecutive_failures = result.success? ? 0 : consecutive_failures + 1
        consecutive_issues = problem ? consecutive_issues + 1 : 0
        hard_failure = consecutive_failures >= ProbeService::FAILURE_THRESHOLD

        state = state_for(consecutive_failures, consecutive_issues, previous_state)
        previous_state = state

        Entry.new(result: result, hard_failure: hard_failure, state: state, problem: problem)
      end
    end

    def self.latest_state(host)
      latest_result = host.latest_probe_result
      return :unknown if latest_result.nil?

      entries = entries_for_host(host, start_at: 24.hours.ago, end_at: Time.current)
      entries.last&.state || fallback_state(host, latest_result)
    end

    # Public-page counterpart of ProbeService.status_for.
    def self.state_for(consecutive_failures, consecutive_issues, previous_state)
      return :down if consecutive_failures >= ProbeService::FAILURE_THRESHOLD
      return :degraded if consecutive_issues >= Host::DEGRADED_THRESHOLD
      return :operational if consecutive_issues.zero?

      previous_state
    end

    def self.trailing_count(results, &problem)
      results.reverse.take_while(&problem).size
    end
    private_class_method :trailing_count

    def self.fallback_state(host, result)
      return :down unless result.success?
      return :degraded if host.result_degraded?(result)

      :operational
    end
    private_class_method :fallback_state
  end
end
