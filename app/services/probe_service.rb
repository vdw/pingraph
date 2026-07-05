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

  def self.execute(host)
    result = case host.probe_type.to_sym
    when :http
      probe_http(host)
    when :tcp
      probe_tcp(host)
    else
      probe_icmp(host)
    end

    alert = persist_result!(host, result)
    enqueue_notification(alert)
    result
  rescue => e
    Rails.logger.error "[ProbeService] Error probing #{host.address}: #{e.message}"

    result = Result.new(
      probe_type: host.probe_type,
      success: false,
      packet_loss: host.icmp? ? 100 : nil,
      error_message: e.message,
      metadata: {},
      recorded_at: Time.current
    )

    alert = persist_result!(host, result)
    enqueue_notification(alert)
    result
  end

  def self.probe_icmp(host)
    raw_output, _stderr, status = Open3.capture3(
      "ping",
      "-c", ICMP_PACKET_COUNT.to_s,
      "-q",
      "-W", ICMP_PACKET_TIMEOUT.to_s,
      "-w", ICMP_COMMAND_DEADLINE.to_s,
      host.address
    )

    return icmp_failure_result unless status.exitstatus == 0 || status.exitstatus == 1

    loss_match = raw_output.match(/(\d+)% packet loss/)
    packet_loss = loss_match ? loss_match[1].to_i : 100

    latency_match = raw_output.match(%r{rtt min/avg/max/mdev = ([\d.]+)/([\d.]+)/([\d.]+)/})

    min_latency = latency_match ? latency_match[1].to_f : nil
    avg_latency = latency_match ? latency_match[2].to_f : nil
    max_latency = latency_match ? latency_match[3].to_f : nil

    Result.new(
      probe_type: :icmp,
      success: packet_loss < 100,
      latency: avg_latency,
      min_latency: min_latency,
      max_latency: max_latency,
      packet_loss: packet_loss,
      metadata: {},
      recorded_at: Time.current
    )
  rescue => e
    Result.new(
      probe_type: :icmp,
      success: false,
      packet_loss: 100,
      error_message: e.message,
      metadata: {},
      recorded_at: Time.current
    )
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

    Result.new(
      probe_type: :http,
      success: success,
      latency: latency_ms,
      status_code: status_code,
      error_message: success ? nil : "Unexpected HTTP status #{status_code}",
      metadata: { "message" => response.message },
      recorded_at: Time.current
    )
  rescue => e
    Result.new(
      probe_type: :http,
      success: false,
      latency: elapsed_ms(start),
      error_message: e.message,
      metadata: {},
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
      latency: elapsed_ms(start),
      error_message: e.message,
      metadata: { "error_class" => e.class.name },
      recorded_at: Time.current
    )
  end

  # Keep writes minimal to reduce lock contention under SQLite WAL.
  # Returns a NotificationPayload when the status transition warrants an alert, else nil.
  # The payload is enqueued by the caller after this transaction commits.
  def self.persist_result!(host, result)
    alert = nil

    Host.transaction do
      host.probe_results.create!(
        probe_type: result.probe_type,
        success: result.success,
        latency: result.latency,
        min_latency: result.min_latency,
        max_latency: result.max_latency,
        packet_loss: result.packet_loss,
        status_code: result.status_code,
        error_message: result.error_message,
        metadata: result.metadata.to_json,
        recorded_at: result.recorded_at
      )

      if result.success
        failures = 0
        computed_status = host.result_degraded?(result) ? :degraded : :up
      else
        # Atomic SQL increment avoids race condition when concurrent ProbeJobs run
        Host.where(id: host.id).update_all("consecutive_failures = consecutive_failures + 1")
        failures = Host.where(id: host.id).pick(:consecutive_failures)
        computed_status = failures >= FAILURE_THRESHOLD ? :down : :degraded
      end

      host.update_columns(
        status: Host.statuses.fetch(computed_status.to_s),
        last_probed_at: result.recorded_at,
        last_error_message: result.error_message,
        consecutive_failures: failures,
        updated_at: Time.current
      )

      # Decide + advance last_notified_status transactionally; enqueue happens post-commit.
      alert = AlertEvaluator.evaluate(host, result, computed_status)
    end

    alert
  end

  # Enqueued only after persist_result!'s transaction has committed, so a rollback can't
  # emit a phantom alert and the delivery job can't race the commit.
  def self.enqueue_notification(payload)
    return if payload.nil?

    DeliverNotificationJob.perform_later(payload.to_job_args)
  end

  def self.icmp_failure_result
    Result.new(
      probe_type: :icmp,
      success: false,
      packet_loss: 100,
      metadata: {},
      recorded_at: Time.current
    )
  end

  def self.elapsed_ms(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(2)
  end
  private_class_method :persist_result!, :enqueue_notification, :icmp_failure_result, :elapsed_ms
end
