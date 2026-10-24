module NotificationChannels
  # POSTs the alert as JSON to any URL: Home Assistant, n8n, Node-RED or your own script.
  # The body is documented in the README, so add fields rather than renaming them.
  class Webhook < Base
    def deliver(payload)
      post_json(setting.webhook_url, build_body(payload))
      :ok
    end

    private

    def build_body(payload)
      {
        "event" => payload.event.to_s,
        "status" => payload.status.to_s,
        "text" => "#{payload.host_name} #{payload.headline}",
        "host" => {
          "id" => payload.host_id,
          "name" => payload.host_name,
          "group" => payload.group_name,
          "url" => payload.host_url
        },
        "error_message" => payload.error_message,
        "packet_loss" => payload.packet_loss,
        "latency_ms" => payload.latency,
        "status_code" => payload.status_code,
        "occurred_at" => payload.occurred_at&.iso8601
      }
    end
  end
end
