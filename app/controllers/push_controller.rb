# GET or POST /api/push/:token, called by cron jobs and scripts to report that they ran. The
# same path and parameters as Uptime Kuma's push monitors: status=up|down, msg, ping (ms).
# Unauthenticated; the token in the URL is the secret.
class PushController < ActionController::API
  rate_limit to: 30, within: 1.minute, by: -> { params[:token] },
    with: -> { render status: :too_many_requests, json: { ok: false, msg: "Too many pushes; slow down." } }

  def create
    host = Host.push.find_by(push_token: params[:token].to_s)
    return render(status: :not_found, json: { ok: false, msg: "No push monitor with this token." }) unless host

    ProbeService.record_push!(host, status: params[:status], message: params[:msg], ping: params[:ping])
    render json: { ok: true }
  end
end
