require "ipaddr"

# Validates the bare network targets handed to external commands (ping, iperf3) and to
# Socket.tcp: an IPv4/IPv6 literal or an RFC 1123 hostname. Anything else is refused, so a
# value like "-f" can never be read as a command-line option.
module NetworkAddress
  MAX_LENGTH = 253
  HOSTNAME_LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i

  module_function

  # Returns the stripped target when valid, else nil.
  def sanitize(value)
    target = value.to_s.strip
    return nil if target.empty? || target.bytesize > MAX_LENGTH

    ip?(target) || hostname?(target) ? target : nil
  end

  def valid?(value)
    !sanitize(value).nil?
  end

  def ip?(value)
    # IPAddr also parses CIDR ("10.0.0.0/24") and zone ids; neither is a single target.
    return false if value.include?("/") || value.include?("%")
    return false unless value.match?(/\A[0-9a-f.:]+\z/i)

    IPAddr.new(value)
    true
  rescue IPAddr::Error
    false
  end

  def hostname?(value)
    return false if value.start_with?(".", "-") || value.end_with?(".")

    labels = value.split(".")
    labels.any? && labels.all? { |label| label.match?(HOSTNAME_LABEL) }
  end
end
