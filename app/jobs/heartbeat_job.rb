require "net/http"
require "uri"

# Dead man's switch: every minute (config/recurring.yml), GETs Settings' heartbeat URL (e.g. a
# healthchecks.io check) while probing is healthy. If Pingraph dies or stops probing, the
# pings stop and the external service alerts. Runs on the notifications queue, which has its
# own worker, so a busy probe queue doesn't delay it.
class HeartbeatJob < ApplicationJob
  queue_as :notifications
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  def perform
    url = Setting.current.heartbeat_url
    return if url.blank? || ProbeHealth.stalled?

    ping(url)
  rescue StandardError => e
    # The next run is a minute away; a missed ping is what the external service watches for.
    Rails.logger.warn "[HeartbeatJob] Heartbeat failed: #{e.class}: #{e.message}"
  end

  private

  def ping(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.is_a?(URI::HTTPS)
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    response = http.request(Net::HTTP::Get.new(uri.request_uri.presence || "/", "User-Agent" => "Pingraph"))

    Rails.logger.warn "[HeartbeatJob] Heartbeat URL responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  end
end
