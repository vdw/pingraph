# Decides whether a probe result's computed status warrants an alert, comparing it against
# the last state the user was notified about (Host#last_notified_status).
#
# Must be called inside the probe-persist transaction: when an alert fires it advances
# last_notified_status transactionally, so concurrent probes cannot double-notify. Returns
# a NotificationPayload to enqueue, or nil when no alert should fire.
#
# Transition rules (last_notified -> new status):
#   * -> down                         => Down alert
#   * -> degraded (if notify_on_degraded) => Degraded alert
#   down/degraded -> up               => Recovery alert
#   unknown/up -> up                  => nothing (host merely came online)
#   same -> same                      => nothing (de-duplicated)
class AlertEvaluator
  RECOVERABLE_FROM = %i[down degraded].freeze

  def self.evaluate(host, result, computed_status)
    new(host, result, computed_status).evaluate
  end

  def initialize(host, result, computed_status)
    @host = host
    @result = result
    @new_status = computed_status.to_sym
  end

  def evaluate
    return nil unless host.notifications_enabled?

    last = host.last_notified_status.to_sym
    return nil if new_status == last

    event = event_for(last)
    return nil if event.nil?
    return nil if event == :degraded && !host.notify_on_degraded?

    host.update_columns(
      last_notified_status: Host.last_notified_statuses.fetch(new_status.to_s),
      updated_at: Time.current
    )

    build_payload(event)
  end

  private

  attr_reader :host, :result, :new_status

  def event_for(last)
    case new_status
    when :down then :down
    when :degraded then :degraded
    when :up then RECOVERABLE_FROM.include?(last) ? :recovery : nil
    end
  end

  def build_payload(event)
    setting = Setting.current

    NotificationPayload.new(
      host_id: host.id,
      host_name: host.name,
      group_name: host.group.name,
      status: new_status,
      event: event,
      error_message: result.error_message,
      packet_loss: result.packet_loss,
      latency: result.latency,
      status_code: result.status_code,
      host_url: setting.absolute_url("/hosts/#{host.id}"),
      occurred_at: result.recorded_at || Time.current
    )
  end
end
