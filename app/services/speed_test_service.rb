require "json"
require "open3"

class SpeedTestService
  TEST_DURATION_SECONDS = 5

  Result = Struct.new(:success?, :bandwidth_mbps, :protocol, keyword_init: true)

  def self.execute(host)
    target = sanitized_target(host.address)
    unless target
      Rails.logger.warn "[SpeedTestService] Refusing unsafe target: #{host.address.inspect}"
      return Result.new(success?: false)
    end

    unless iperf3_installed?
      Rails.logger.warn "[SpeedTestService] iperf3 is not installed; skipping host #{host.id}"
      return Result.new(success?: false)
    end

    stdout, stderr, status = Open3.capture3(
      "iperf3",
      "-c", target,
      "-J",
      "-t", TEST_DURATION_SECONDS.to_s
    )

    unless status.success?
      Rails.logger.warn "[SpeedTestService] iperf3 failed for host #{host.id}: #{stderr.strip}"
      return Result.new(success?: false)
    end

    payload = JSON.parse(stdout)
    bits_per_second = extract_bits_per_second(payload)
    unless bits_per_second
      Rails.logger.warn "[SpeedTestService] Unable to find receiver bits_per_second for host #{host.id}"
      return Result.new(success?: false)
    end

    Result.new(
      success?: true,
      bandwidth_mbps: (bits_per_second.to_f / 1_000_000.0).round(2),
      protocol: "tcp"
    )
  rescue JSON::ParserError => e
    Rails.logger.warn "[SpeedTestService] Invalid JSON output for host #{host.id}: #{e.message}"
    Result.new(success?: false)
  rescue Errno::ENOENT
    Rails.logger.warn "[SpeedTestService] iperf3 executable not found"
    Result.new(success?: false)
  rescue => e
    Rails.logger.error "[SpeedTestService] Unexpected error for host #{host.id}: #{e.message}"
    Result.new(success?: false)
  end

  private

  def self.iperf3_installed?
    _stdout, _stderr, status = Open3.capture3("iperf3", "--version")
    status.success?
  rescue Errno::ENOENT
    false
  end

  def self.sanitized_target(address)
    target = address.to_s.strip
    return nil if target.empty? || target.bytesize > 253

    return target if ipv4?(target)
    return target if ipv6?(target)
    return target if hostname?(target)

    nil
  end

  def self.ipv4?(value)
    value.match?(/\A(?:\d{1,3}\.){3}\d{1,3}\z/) && value.split(".").all? { |part| part.to_i.between?(0, 255) }
  end

  def self.ipv6?(value)
    value.match?(/\A[0-9a-f:]+\z/i) && value.include?(":")
  end

  def self.hostname?(value)
    return false if value.start_with?(".") || value.end_with?(".")

    labels = value.split(".")
    return false if labels.empty?

    labels.all? do |label|
      label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i)
    end
  end

  def self.extract_bits_per_second(payload)
    payload.dig("end", "sum_received", "bits_per_second") ||
      payload.dig("end", "streams", 0, "receiver", "bits_per_second") ||
      payload.dig("end", "sum", "bits_per_second")
  end
end
