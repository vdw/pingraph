# GET /health, for Docker's HEALTHCHECK and external uptime monitors. Unlike /up (the app
# booted), this also fails when probing has stopped, e.g. the background worker isn't running.
# Unauthenticated, so it reports only coarse status.
class HealthController < ActionController::Base
  def show
    stalled = ProbeHealth.stalled?
    last_poll_at = ProbeHealth.last_poll_at

    render status: stalled ? :service_unavailable : :ok, json: {
      status: stalled ? "stalled" : "ok",
      last_poll_at: last_poll_at&.iso8601,
      falling_behind: ProbeHealth.falling_behind?
    }
  rescue ActiveRecord::ActiveRecordError => e
    render status: :service_unavailable, json: { status: "error", error: e.class.name }
  end
end
