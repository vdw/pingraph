module NotificationChannels
  class Slack < Base
    COLORS = { down: "#dc2626", degraded: "#d97706", recovery: "#16a34a", cert_expiring: "#d97706" }.freeze
    DEFAULT_COLOR = "#6b7280".freeze

    def deliver(payload)
      post_json(setting.slack_webhook_url, build_body(payload))
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
