# Immutable snapshot of an alert-worthy event, captured at trigger time and passed by
# value into DeliverNotificationJob. It is deliberately NOT re-derived from live host
# state at delivery time — a host that recovers before the job runs must not turn a
# "Down" alert into a healthy-looking message.
NotificationPayload = Data.define(
  :host_id,
  :host_name,
  :group_name,
  :status,          # transition target: :up | :degraded | :down
  :event,           # :down | :degraded | :recovery
  :error_message,
  :packet_loss,
  :latency,
  :status_code,
  :host_url,
  :occurred_at
) do
  # Primitive, string-keyed hash safe to pass as ActiveJob arguments across any adapter.
  def to_job_args
    {
      "host_id" => host_id,
      "host_name" => host_name,
      "group_name" => group_name,
      "status" => status&.to_s,
      "event" => event&.to_s,
      "error_message" => error_message,
      "packet_loss" => packet_loss,
      "latency" => latency,
      "status_code" => status_code,
      "host_url" => host_url,
      "occurred_at" => occurred_at&.iso8601
    }
  end

  def self.from_job_args(args)
    args = args.with_indifferent_access
    new(
      host_id: args[:host_id],
      host_name: args[:host_name],
      group_name: args[:group_name],
      status: args[:status]&.to_sym,
      event: args[:event]&.to_sym,
      error_message: args[:error_message],
      packet_loss: args[:packet_loss],
      latency: args[:latency],
      status_code: args[:status_code],
      host_url: args[:host_url],
      occurred_at: (Time.zone.parse(args[:occurred_at]) if args[:occurred_at].present?)
    )
  end

  # Human-readable summary reused across channels (Slack text, email subject).
  def headline
    case event
    when :down then "is DOWN"
    when :degraded then "is DEGRADED"
    when :recovery then "has RECOVERED"
    else status.to_s.upcase
    end
  end
end
