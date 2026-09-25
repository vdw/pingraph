require "json"
require "open3"

class SpeedTestService
  TEST_DURATION_SECONDS = 5

  Result = Struct.new(:success?, :bandwidth_mbps, :protocol, :error_message, keyword_init: true)

  def self.execute(host)
    target = sanitized_target(host.address)
    unless target
      Rails.logger.warn "[SpeedTestService] Refusing unsafe target: #{host.address.inspect}"
      return failure("Address #{host.address.inspect} is not a plain hostname or IP address")
    end

    unless iperf3_installed?
      Rails.logger.warn "[SpeedTestService] iperf3 is not installed; skipping host #{host.id}"
      return failure("iperf3 is not installed on the Pingraph server")
    end

    stdout, stderr, status = Open3.capture3(
      "iperf3",
      "-c", target,
      "-J",
      "-t", TEST_DURATION_SECONDS.to_s
    )

    unless status.success?
      Rails.logger.warn "[SpeedTestService] iperf3 failed for host #{host.id}: #{stderr.strip}"
      return failure(iperf3_error(stdout, stderr))
    end

    payload = JSON.parse(stdout)
    bits_per_second = extract_bits_per_second(payload)
    unless bits_per_second
      Rails.logger.warn "[SpeedTestService] Unable to find receiver bits_per_second for host #{host.id}"
      return failure("iperf3 finished but reported no bandwidth")
    end

    Result.new(
      success?: true,
      bandwidth_mbps: (bits_per_second.to_f / 1_000_000.0).round(2),
      protocol: "tcp"
    )
  rescue JSON::ParserError => e
    Rails.logger.warn "[SpeedTestService] Invalid JSON output for host #{host.id}: #{e.message}"
    failure("iperf3 returned unreadable output")
  rescue Errno::ENOENT
    Rails.logger.warn "[SpeedTestService] iperf3 executable not found"
    failure("iperf3 is not installed on the Pingraph server")
  rescue => e
    Rails.logger.error "[SpeedTestService] Unexpected error for host #{host.id}: #{e.message}"
    failure(e.message)
  end

  private

  def self.iperf3_installed?
    _stdout, _stderr, status = Open3.capture3("iperf3", "--version")
    status.success?
  rescue Errno::ENOENT
    false
  end

  def self.failure(message)
    Result.new(success?: false, error_message: message)
  end

  # iperf3 -J reports errors in the JSON body ("error": "unable to connect to server: ..."),
  # with stderr as a fallback for failures before JSON output starts.
  def self.iperf3_error(stdout, stderr)
    json_error = begin
      JSON.parse(stdout)["error"]
    rescue JSON::ParserError, TypeError
      nil
    end

    message = json_error.presence || stderr.to_s.strip.presence || "iperf3 failed"
    message = "#{message} (is an iperf3 server running on the target? Start one with `iperf3 -s`)" if message.include?("unable to connect")
    message.truncate(500)
  end

  def self.sanitized_target(address)
    NetworkAddress.sanitize(address)
  end

  def self.extract_bits_per_second(payload)
    payload.dig("end", "sum_received", "bits_per_second") ||
      payload.dig("end", "streams", 0, "receiver", "bits_per_second") ||
      payload.dig("end", "sum", "bits_per_second")
  end
end
