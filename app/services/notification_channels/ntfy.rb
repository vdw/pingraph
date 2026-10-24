module NotificationChannels
  # Publishes to an ntfy topic (ntfy.sh or self-hosted). Uses ntfy's JSON publishing, which
  # takes the topic in the body and is posted to the server's root, so host names with
  # non-ASCII characters don't have to fit in HTTP headers.
  class Ntfy < Base
    # ntfy priorities: 3 is default, 4 is high (long vibration and a pop-over on Android).
    PRIORITIES = { down: 4, degraded: 3, recovery: 3 }.freeze
    # ntfy shows these tags as emoji in front of the title.
    TAGS = { down: "red_circle", degraded: "yellow_circle", recovery: "green_circle" }.freeze

    def deliver(payload)
      server_url, topic = split_url(setting.ntfy_url)
      headers = setting.ntfy_token.present? ? { "Authorization" => "Bearer #{setting.ntfy_token}" } : {}

      post_json(server_url, {
        "topic" => topic,
        "title" => "#{payload.host_name} #{payload.headline}",
        "message" => detail_lines(payload).map { |label, value| "#{label}: #{value}" }.join("\n"),
        "priority" => PRIORITIES.fetch(payload.event, 3),
        "tags" => [ TAGS.fetch(payload.event, "white_circle") ],
        "click" => payload.host_url
      }.compact, headers: headers)
      :ok
    end

    private

    # "https://ntfy.example.com/alerts" -> ["https://ntfy.example.com/", "alerts"]
    def split_url(url)
      server, _, topic = url.chomp("/").rpartition("/")
      [ "#{server}/", topic ]
    end
  end
end
