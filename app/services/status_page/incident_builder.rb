module StatusPage
  class IncidentBuilder
    Incident = Struct.new(:host, :group, :state, :start_at, :end_at, :message, keyword_init: true) do
      def duration
        (end_at || Time.current) - start_at
      end

      def ongoing?
        end_at.nil?
      end
    end

    def self.call(hosts, start_at: 7.days.ago, end_at: Time.current)
      hosts.flat_map { |host| incidents_for_host(host, start_at: start_at, end_at: end_at) }
        .sort_by(&:start_at)
        .reverse
    end

    def self.incidents_for_host(host, start_at:, end_at:)
      entries = ResultStateCalculator.entries_for_host(host, start_at: start_at, end_at: end_at)
      incidents = []
      current = nil

      entries.each do |entry|
        if entry.state == :operational
          if current
            current[:end_at] = entry.result.recorded_at
            incidents << build_incident(host, current)
            current = nil
          end
          next
        end

        if current
          current[:last_at] = entry.result.recorded_at
          current[:state] = worse_state(current[:state], entry.state)
          current[:message] = message_for(host, entry)
          next
        end

        current = {
          state: entry.state,
          start_at: entry.result.recorded_at,
          last_at: entry.result.recorded_at,
          message: message_for(host, entry)
        }
      end

      incidents << build_incident(host, current, ongoing: true) if current
      incidents
    end

    def self.build_incident(host, current, ongoing: false)
      return unless current

      Incident.new(
        host: host,
        group: host.group,
        state: current[:state],
        start_at: current[:start_at],
        end_at: ongoing ? nil : current[:end_at] || current[:last_at],
        message: current[:message]
      )
    end
    private_class_method :build_incident

    def self.message_for(host, entry)
      result = entry.result
      return result.error_message if result.error_message.present?
      return "Packet loss reached #{result.packet_loss}%" if result.icmp? && result.packet_loss.to_i >= 5
      return "High latency observed (#{result.latency.round(1)} ms)" if result.latency.present? && result.latency.to_f > host.latency_threshold_ms.to_f
      return "Unexpected HTTP status #{result.status_code}" if result.http? && result.status_code.present?

      entry.state == :down ? "Probe failure detected" : "Performance degradation detected"
    end
    private_class_method :message_for

    def self.worse_state(left, right)
      priorities = { degraded: 1, down: 2 }
      priorities.fetch(right, 0) > priorities.fetch(left, 0) ? right : left
    end
    private_class_method :worse_state
  end
end
