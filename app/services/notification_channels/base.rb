module NotificationChannels
  # Abstract channel. Subclasses format a NotificationPayload for a specific transport and
  # implement #deliver, raising DeliveryError (or any exception) on failure so the
  # dispatcher can isolate and report it.
  class Base
    class DeliveryError < StandardError; end

    def initialize(setting)
      @setting = setting
    end

    def deliver(_payload)
      raise NotImplementedError, "#{self.class} must implement #deliver"
    end

    private

    attr_reader :setting

    def subject(payload)
      "[Pingraph] #{payload.host_name} #{payload.headline}"
    end

    def status_emoji(event)
      case event
      when :down then "🔴"
      when :degraded then "🟡"
      when :recovery then "🟢"
      else "⚪"
      end
    end

    # Ordered [label, value] detail rows shared by channels. Only present values included.
    def detail_lines(payload)
      lines = []
      lines << [ "Group", payload.group_name ] if payload.group_name.present?
      lines << [ "Status", payload.status.to_s.capitalize ]
      lines << [ "Error", payload.error_message ] if payload.error_message.present?
      lines << [ "Packet loss", "#{payload.packet_loss}%" ] if payload.packet_loss.to_i.positive?
      lines << [ "Latency", "#{payload.latency.round(1)} ms" ] if payload.latency.present?
      lines << [ "HTTP status", payload.status_code ] if payload.status_code.present?
      lines
    end
  end
end
