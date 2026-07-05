require "net/http"
require "uri"

module NotificationChannels
  class Slack < Base
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    COLORS = { down: "#dc2626", degraded: "#d97706", recovery: "#16a34a" }.freeze
    DEFAULT_COLOR = "#6b7280".freeze

    def deliver(payload)
      uri = URI.parse(setting.slack_webhook_url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.is_a?(URI::HTTPS)
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri.presence || "/", "Content-Type" => "application/json")
      request.body = build_body(payload).to_json
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise DeliveryError, "Slack webhook responded #{response.code}: #{response.body.to_s.truncate(200)}"
      end

      :ok
    end

    private

    def build_body(payload)
      lines = [ "#{status_emoji(payload.event)} *#{payload.host_name}* #{payload.headline}" ]
      lines << "<#{payload.host_url}|View in Pingraph>" if payload.host_url.present?

      fields = detail_lines(payload).map do |title, value|
        { "title" => title, "value" => value.to_s, "short" => title != "Error" }
      end

      {
        "text" => lines.join("\n"),
        "attachments" => [ {
          "color" => COLORS.fetch(payload.event, DEFAULT_COLOR),
          "fields" => fields,
          "footer" => "Pingraph"
        } ]
      }
    end
  end
end
