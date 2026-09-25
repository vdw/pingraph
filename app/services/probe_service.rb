require "net/http"
require "open3"
require "socket"
require "timeout"
require "uri"
require "openssl"

class ProbeService
  Result = Struct.new(
    :probe_type,
    :success,
    :latency,
    :min_latency,
    :max_latency,
    :packet_loss,
    :jitter,
    :status_code,
    :error_message,
    :metadata,
    :recorded_at,
    keyword_init: true
  )

  ICMP_PACKET_COUNT = 5
  ICMP_PACKET_TIMEOUT = 2
  ICMP_COMMAND_DEADLINE = ICMP_PACKET_COUNT * ICMP_PACKET_TIMEOUT
  TCP_TIMEOUT = 5
  HTTP_OPEN_TIMEOUT = 5
  HTTP_READ_TIMEOUT = 5
  FAILURE_THRESHOLD = 2

  # iputils: "rtt min/avg/max/mdev = 1/2/3/4 ms"; BSD/macOS: "round-trip min/avg/max/stddev";
  # BusyBox: "round-trip min/avg/max = 1/2/3 ms" (no jitter).
  ICMP_RTT_PATTERN = %r{(?:rtt|round-trip) min/avg/max(?:/(?:mdev|stddev))? = ([\d.]+)/([\d.]+)/([\d.]+)(?:/([\d.]+))?}

  def self.execute(host)
    result = run_probe(host)

    # Deliberately outside run_probe's rescue: a database error while saving (e.g. SQLite
    # busy) must raise and be retried by ProbeJob, never be recorded as a host failure.
    deliveries = persist_result!(host, result)
    enqueue_notifications(deliveries)
    result
  end

  def self.run_probe(host)
    case host.probe_type.to_sym
    when :http
      probe_http(host)
    when :tcp
      probe_tcp(host)
    else
      probe_icmp(host)
    end
  rescue => e
    Rails.logger.error "[ProbeService] Error probing #{host.address}: #{e.message}"

    Result.new(
      probe_type: host.probe_type,
      success: false,
      packet_loss: host.icmp? ? 100 : nil,
      error_message: e.message,
      metadata: {},
      recorded_at: Time.current
    )
  end

  def self.probe_icmp(host)
    raw_output, stderr, status = Open3.capture3(
      "ping",
      "-c", ICMP_PACKET_COUNT.to_s,
      "-q",
      "-W", ICMP_PACKET_TIMEOUT.to_s,
      "-w", ICMP_COMMAND_DEADLINE.to_s,
      "--", # the address can never be parsed as an option
      host.address
    )

    # Exit 1 = ran but got no (or partial) replies; anything else = ping itself failed
    # (unknown host, network unreachable, permission denied, ...).
    unless status.exitstatus == 0 || status.exitstatus == 1
      return icmp_failure_result(ping_error_message(stderr, raw_output, status))
    end

    loss_match = raw_output.match(/(\d+(?:\.\d+)?)% packet loss/)
    packet_loss = loss_match ? loss_match[1].to_f.round : 100

    latency_match = raw_output.match(ICMP_RTT_PATTERN)

    Result.new(
      probe_type: :icmp,
      success: packet_loss < 100,
      latency: latency_match && latency_match[2].to_f,
      min_latency: latency_match && latency_match[1].to_f,
      max_latency: latency_match && latency_match[3].to_f,
      jitter: latency_match && latency_match[4]&.to_f,
      packet_loss: packet_loss,
      error_message: packet_loss >= 100 ? "No reply (100% packet loss)" : nil,
      metadata: {},
      recorded_at: Time.current
    )
  rescue => e
    icmp_failure_result(e.message)
  end

  def self.probe_http(host)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    uri = URI.parse(host.normalized_http_address)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = HTTP_OPEN_TIMEOUT
    http.read_timeout = HTTP_READ_TIMEOUT
    http.use_ssl = uri.scheme == "https"
    http.verify_mode = host.verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(uri.request_uri.presence || "/")
    response = http.request(request)

    latency_ms = elapsed_ms(start)
    status_code = response.code.to_i
    success = host.http_status_matches?(status_code)

    # Latency only describes successful checks; for failures the elapsed time goes to
    # metadata so charts and averages are not skewed by timeouts or instant refusals.
    Result.new(
      probe_type: :http,
      success: success,
      latency: success ? latency_ms : nil,
      status_code: status_code,
      error_message: success ? nil : "Unexpected HTTP status #{status_code}",
      metadata: success ? { "message" => response.message } : { "message" => response.message, "elapsed_ms" => latency_ms },
      recorded_at: Time.current
    )
  rescue => e
    Result.new(
      probe_type: :http,
      success: false,
      error_message: e.message,
      metadata: { "error_class" => e.class.name, "elapsed_ms" => start && elapsed_ms(start) }.compact,
      recorded_at: Time.current
    )
  end

  def self.probe_tcp(host)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Socket.tcp(host.address, host.port, connect_timeout: TCP_TIMEOUT) do |socket|
      socket.close
    end

    Result.new(
      probe_type: :tcp,
      success: true,
      latency: elapsed_ms(start),
      metadata: {},
      recorded_at: Time.current
    )
  rescue SystemCallError, IOError, SocketError, Timeout::Error => e
    Result.new(
      probe_type: :tcp,
      success: false,
      error_message: e.message,
      metadata: { "error_class" => e.class.name, "elapsed_ms" => elapsed_ms(start) },
      recorded_at: Time.current
    )
  end

  # Status from consecutive samples:
  #   FAILURE_THRESHOLD failures in a row                  => down
  #   Host::DEGRADED_THRESHOLD problem samples in a row    => degraded (failed, slow or lossy)
  #   a clean sample                                       => up
  #   a single problem sample                              => unchanged (not enough evidence)
  def self.status_for(current_status, failures, issues)
    return :down if failures >= FAILURE_THRESHOLD
    return :degraded if issues >= Host::DEGRADED_THRESHOLD
    return :up if issues.zero?

    current_status.to_sym
  end

  # Keep writes minimal to reduce lock contention under SQLite WAL.
  # Returns the NotificationDelivery rows created for this result (one per enabled channel)
  # when the status transition warrants an alert. They are created in the same transaction
  # that advances last_notified_status, so an alert is never decided without being recorded;
  # the caller enqueues their jobs after commit.
  def self.persist_result!(host, result)
    deliveries = []

    Host.transaction do
      host.probe_results.create!(
        probe_type: result.probe_type,
        success: result.success,
        latency: result.latency,
        min_latency: result.min_latency,
        max_latency: result.max_latency,
        jitter: result.jitter,
        packet_loss: result.packet_loss,
        status_code: result.status_code,
        error_message: result.error_message,
        metadata: result.metadata.to_json,
        recorded_at: result.recorded_at
      )

      problem = host.result_degraded?(result)

      # Atomic SQL update avoids lost increments if two ProbeJobs for a host ever overlap.
      Host.where(id: host.id).update_all([
        "consecutive_failures = CASE WHEN ? THEN 0 ELSE consecutive_failures + 1 END, " \
        "consecutive_issues = CASE WHEN ? THEN consecutive_issues + 1 ELSE 0 END",
        result.success ? true : false, problem
      ])
      failures, issues, current_status = Host.where(id: host.id).pick(:consecutive_failures, :consecutive_issues, :status)
      computed_status = status_for(current_status, failures, issues)

      host.update_columns(
        status: Host.statuses.fetch(computed_status.to_s),
        last_probed_at: result.recorded_at,
        last_error_message: result.error_message,
        consecutive_failures: failures,
        consecutive_issues: issues,
        updated_at: Time.current
      )

      alert = AlertEvaluator.evaluate(host, result, computed_status)
      deliveries = NotificationDelivery.create_for!(alert) if alert
    end

    deliveries
  end

  # Enqueued only after persist_result!'s transaction has committed, so a rollback can't
  # emit a phantom alert and the delivery job can't race the commit.
  def self.enqueue_notifications(deliveries)
    deliveries.each { |delivery| DeliverNotificationJob.perform_later(delivery.id) }
  end

  def self.icmp_failure_result(error_message = nil)
    Result.new(
      probe_type: :icmp,
      success: false,
      packet_loss: 100,
      error_message: error_message.presence || "Ping failed",
      metadata: {},
      recorded_at: Time.current
    )
  end

  # "ping: nas.local: Name or service not known" -> "nas.local: Name or service not known"
  def self.ping_error_message(stderr, stdout, status)
    line = stderr.to_s.strip.lines.last.presence || stdout.to_s.strip.lines.last.presence
    message = line&.strip&.delete_prefix("ping: ")
    message.presence || "ping exited with status #{status.exitstatus}"
  end

  def self.elapsed_ms(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(2)
  end
  private_class_method :persist_result!, :enqueue_notifications, :icmp_failure_result, :ping_error_message, :elapsed_ms
end
