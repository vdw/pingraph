module NotificationChannels
  # Sends through a Telegram bot (created with @BotFather) to a chat, group or channel the
  # bot can post in, using the Bot API's HTML formatting.
  class Telegram < Base
    API_URL = "https://api.telegram.org".freeze

    def deliver(payload)
      post_json("#{API_URL}/bot#{setting.telegram_bot_token}/sendMessage", {
        "chat_id" => setting.telegram_chat_id,
        "text" => build_text(payload),
        "parse_mode" => "HTML",
        "link_preview_options" => { "is_disabled" => true }
      })
      :ok
    end

    private

    def build_text(payload)
      lines = [ "#{status_emoji(payload.event)} <b>#{escape(payload.host_name)}</b> #{escape(payload.headline)}" ]
      detail_lines(payload).each { |label, value| lines << "#{label}: #{escape(value)}" }
      lines << %(<a href="#{escape(payload.host_url)}">View in Pingraph</a>) if payload.host_url.present?
      lines.join("\n")
    end

    def escape(value)
      ERB::Util.html_escape(value.to_s)
    end
  end
end
