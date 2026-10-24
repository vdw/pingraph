require "net/http"
require "uri"

module NotificationChannels
  # Abstract channel. Subclasses format a NotificationPayload for a specific transport and
  # implement #deliver, raising DeliveryError (or any exception) on failure so the
  # dispatcher can isolate and report it.
  class Base
    class DeliveryError < StandardError; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5

    def initialize(setting)
      @setting = setting
    end

    def deliver(_payload)
      raise NotImplementedError, "#{self.class} must implement #deliver"
    end

    private

    attr_reader :setting

    # POSTs body as JSON and raises DeliveryError unless the response is 2xx. The error names
    # only the host, never the URL: some URLs carry a secret (Telegram's bot token, a webhook
    # or ntfy topic), and the message is shown in the notification log.
    def post_json(url, body, headers: {})
      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.is_a?(URI::HTTPS)
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri.presence || "/",
        { "Content-Type" => "application/json", "User-Agent" => "Pingraph" }.merge(headers))
      request.body = body.to_json
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise DeliveryError, "#{uri.host} responded #{response.code}: #{response.body.to_s.truncate(200)}"
      end

      response
    end

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
