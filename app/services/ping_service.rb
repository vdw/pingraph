require "open3"

class PingService
  # Number of ICMP packets per probe
  PACKET_COUNT = 5
  # Timeout per packet (seconds)
  PACKET_TIMEOUT = 2
  # Hard timeout for the whole command (seconds)
  COMMAND_DEADLINE = PACKET_COUNT * PACKET_TIMEOUT

  def self.execute(host)
    raw_output, _stderr, status = Open3.capture3(
      "ping",
      "-c", PACKET_COUNT.to_s,
      "-q",
      "-W", PACKET_TIMEOUT.to_s,
      "-w", COMMAND_DEADLINE.to_s,
      host.address
    )

    # exit 0 = all packets received, exit 1 = partial loss — both are parseable
    if status.exitstatus == 0 || status.exitstatus == 1
      parse_results(host, raw_output)
    else
      # Total failure: host unreachable, DNS error, etc.
      record_failure(host)
    end
  rescue => e
    Rails.logger.error "[PingService] Error pinging #{host.address}: #{e.message}"
    record_failure(host)
  end

  private

  def self.parse_results(host, output)
    # "5 packets transmitted, 3 received, 40% packet loss, ..."
    loss_match = output.match(/(\d+)% packet loss/)
    packet_loss = loss_match ? loss_match[1].to_i : 100

    # "rtt min/avg/max/mdev = 12.345/15.678/18.910/2.123 ms"
    latency_match = output.match(%r{rtt min/avg/max/mdev = ([\d.]+)/([\d.]+)/([\d.]+)/})

    min_latency = latency_match ? latency_match[1].to_f : nil
    avg_latency = latency_match ? latency_match[2].to_f : nil
    max_latency = latency_match ? latency_match[3].to_f : nil

    host.pings.create!(
      latency:      avg_latency,
      min_latency:  min_latency,
      max_latency:  max_latency,
      packet_loss:  packet_loss,
      recorded_at:  Time.current
    )
  end

  def self.record_failure(host)
    host.pings.create!(
      latency:      nil,
      min_latency:  nil,
      max_latency:  nil,
      packet_loss:  100,
      recorded_at:  Time.current
    )
  end
end
