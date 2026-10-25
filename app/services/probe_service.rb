require "io/wait"
require "net/http"
require "open3"
require "resolv"
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
    :certificate_expires_at, # HTTPS only: the server certificate's not_after
    keyword_init: true
  )

  ICMP_PACKET_COUNT = 5
  # Seconds between packets: 0.2 is the lowest iputils allows without root, so a healthy
  # probe takes about 1 second instead of 4 and each worker thread covers ~4x more hosts.
  ICMP_PACKET_INTERVAL = 0.2
  ICMP_PACKET_TIMEOUT = 2
  # Time to send every packet and wait for the last reply. With -w, ping keeps sending until
  # it has ICMP_PACKET_COUNT replies or the deadline passes, so this also caps how long an
  # unreachable host takes (3 seconds, down from 10).
  ICMP_COMMAND_DEADLINE = ((ICMP_PACKET_COUNT - 1) * ICMP_PACKET_INTERVAL + ICMP_PACKET_TIMEOUT).ceil
  # Keyword checks read at most this much of the body.
  HTTP_BODY_LIMIT = 1.megabyte
  HTTP_REQUEST_CLASSES = {
    "GET" => Net::HTTP::Get, "HEAD" => Net::HTTP::Head, "POST" => Net::HTTP::Post, "PUT" => Net::HTTP::Put,
    "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete, "OPTIONS" => Net::HTTP::Options
  }.freeze
  REDIRECT_CODES = [ 301, 302, 303, 307, 308 ].freeze
  DNS_RESOURCE_CLASSES = {
    "A" => Resolv::DNS::Resource::IN::A, "AAAA" => Resolv::DNS::Resource::IN::AAAA,
    "CNAME" => Resolv::DNS::Resource::IN::CNAME, "MX" => Resolv::DNS::Resource::IN::MX,
    "NS" => Resolv::DNS::Resource::IN::NS, "TXT" => Resolv::DNS::Resource::IN::TXT
  }.freeze
  # A push that arrives up to this long after the interval still counts, so a cron job
  # running a few seconds late doesn't fail the check.
  PUSH_GRACE = 10.seconds
  # Docker and Redis replies are read up to this size (a container inspect is ~10-30 KB).
  SOCKET_READ_LIMIT = 1.megabyte

  # iputils: "rtt min/avg/max/mdev = 1/2/3/4 ms"; BSD/macOS: "round-trip min/avg/max/stddev";
  # BusyBox: "round-trip min/avg/max = 1/2/3 ms" (no jitter).
  ICMP_RTT_PATTERN = %r{(?:rtt|round-trip) min/avg/max(?:/(?:mdev|stddev))? = ([\d.]+)/([\d.]+)/([\d.]+)(?:/([\d.]+))?}

  def self.execute(host)
    result = run_probe(host)
    # A push host that received a push recently: the push itself was already recorded.
    return if result.nil?

    record!(host, result)
  end

  # Saves a result, from a check or a push, and sends the alerts it triggers.
  def self.record!(host, result)
    # Deliberately outside run_probe's rescue: a database error while saving (e.g. SQLite
    # busy) must raise and be retried by ProbeJob, never be recorded as a host failure.
    deliveries = persist_result!(host, result)
    enqueue_notifications(deliveries)
    result
  end

  # A push to /api/push/:token, in Uptime Kuma's format: status "up" (the default) or
  # "down", an optional message, and an optional ping in milliseconds.
  def self.record_push!(host, status: nil, message: nil, ping: nil)
    down = status.to_s.strip.downcase == "down"
    message = message.to_s.strip.truncate(255).presence
    latency = Float(ping, exception: false) unless down
    latency = nil unless latency&.finite? && latency >= 0

    result = Result.new(
      probe_type: :push,
      success: !down,
      latency: latency,
      error_message: down ? (message || "Reported down") : nil,
      metadata: { "message" => message }.compact,
      recorded_at: Time.current
    )
    host.update_column(:push_received_at, result.recorded_at)
    record!(host, result)
  end

  def self.run_probe(host)
    case host.probe_type.to_sym
    when :http
      probe_http(host)
    when :tcp
      probe_tcp(host)
    when :dns
      probe_dns(host)
    when :push
      probe_push(host)
    when :docker
      probe_docker(host)
    when :redis
      probe_redis(host)
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
      "-i", ICMP_PACKET_INTERVAL.to_s,
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

  # Follows up to host.max_redirects redirects and matches the final response against the
  # expected status and keyword. The certificate expiry comes from the first request, the
  # URL actually being monitored.
  def self.probe_http(host)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    uri = URI.parse(host.normalized_http_address)
    method = host.http_method.presence || "GET"
    body = host.request_body
    redirects = 0
    certificate_expires_at = nil

    loop do
      response, response_body, certificate = http_request(host, uri, method, body, same_origin: redirects.zero?)
      certificate_expires_at = certificate&.not_after if redirects.zero?

      location = response["location"] if REDIRECT_CODES.include?(response.code.to_i)
      if location.present? && redirects < host.max_redirects.to_i
        uri = redirect_uri(uri, location)
        redirects += 1
        # 301/302/303 turn into GET without a body, as browsers do; 307/308 repeat the request.
        unless [ 307, 308 ].include?(response.code.to_i)
          method = "GET"
          body = nil
        end
        next
      end

      return http_result(host, response, response_body, start, redirects, certificate_expires_at,
        too_many_redirects: location.present? && host.max_redirects.to_i.positive?)
    end
  rescue => e
    Result.new(
      probe_type: :http,
      success: false,
      error_message: e.is_a?(Timeout::Error) ? "Timed out after #{host.timeout_seconds} seconds" : e.message,
      metadata: { "error_class" => e.class.name, "elapsed_ms" => start && elapsed_ms(start) }.compact,
      recorded_at: Time.current
    )
  end

  # One request. Returns [response, body (only read for keyword checks, up to
  # HTTP_BODY_LIMIT), peer certificate]. Custom headers and credentials are sent to the
  # monitored URL's origin only, never to a host a redirect points at.
  def self.http_request(host, uri, method, body, same_origin:)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = host.timeout_seconds
    http.read_timeout = host.timeout_seconds
    http.write_timeout = host.timeout_seconds
    # Net::HTTP silently retries idempotent requests once, doubling the timeout.
    http.max_retries = 0
    http.use_ssl = uri.scheme == "https"
    http.verify_mode = host.verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE

    request = HTTP_REQUEST_CLASSES.fetch(method).new(uri.request_uri.presence || "/", "User-Agent" => "Pingraph")
    if body.present?
      request.body = body
      request["Content-Type"] = json?(body) ? "application/json" : "text/plain"
    end
    if same_origin
      request.basic_auth(host.basic_auth_user, host.basic_auth_password.to_s) if host.basic_auth_user.present?
      host.parsed_request_headers.each { |name, value| request[name] = value }
    end

    http.start do |connection|
      certificate = connection.peer_cert if uri.scheme == "https"
      response = nil
      response_body = String.new

      catch(:body_limit_reached) do
        connection.request(request) do |res|
          response = res
          next if host.keyword.blank?

          res.read_body do |chunk|
            response_body << chunk
            # Stops reading; leaving start's block closes the connection.
            throw :body_limit_reached if response_body.bytesize >= HTTP_BODY_LIMIT
          end
        end
      end

      [ response, response_body.byteslice(0, HTTP_BODY_LIMIT).force_encoding(Encoding::UTF_8), certificate ]
    end
  end

  def self.http_result(host, response, response_body, start, redirects, certificate_expires_at, too_many_redirects:)
    latency_ms = elapsed_ms(start)
    status_code = response.code.to_i
    error_message =
      if too_many_redirects
        "Too many redirects (more than #{host.max_redirects})"
      elsif !host.http_status_matches?(status_code)
        "Unexpected HTTP status #{status_code}"
      elsif host.keyword.present? && !host.keyword_matches?(response_body)
        host.keyword_invert? ? "Keyword \"#{host.keyword}\" was found" : "Keyword \"#{host.keyword}\" not found"
      end
    success = error_message.nil?

    metadata = { "message" => response.message }
    metadata["redirects"] = redirects if redirects.positive?
    # Latency only describes successful checks; for failures the elapsed time goes to
    # metadata so charts and averages are not skewed by timeouts or instant refusals.
    metadata["elapsed_ms"] = latency_ms unless success

    Result.new(
      probe_type: :http,
      success: success,
      latency: success ? latency_ms : nil,
      status_code: status_code,
      error_message: error_message,
      metadata: metadata,
      recorded_at: Time.current,
      certificate_expires_at: certificate_expires_at
    )
  end

  def self.redirect_uri(base, location)
    uri = base.merge(location)
    raise ArgumentError, "Redirect to unsupported URL #{location.truncate(100)}" unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri
  end

  def self.json?(body)
    JSON.parse(body)
    true
  rescue JSON::ParserError
    false
  end

  def self.probe_tcp(host)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Socket.tcp(host.address, host.port, connect_timeout: host.timeout_seconds) do |socket|
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

  # Resolves host.address with the host's resolver (or the system's). Passes when there is at
  # least one record of the type, and one equals dns_expected_value when that is set.
  def self.probe_dns(host)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    config = host.dns_server.present? ? { nameserver: [ host.dns_server ] } : Resolv::DNS::Config.default_config_hash
    records = Resolv::DNS.open(config.merge(raise_timeout_errors: true)) do |dns|
      dns.timeouts = host.timeout_seconds
      dns.getresources(host.address, DNS_RESOURCE_CLASSES.fetch(host.dns_record_type)).map { |record| dns_record_value(record) }
    end
    error_message =
      if records.empty?
        "No #{host.dns_record_type} records found for #{host.address}"
      elsif host.dns_expected_value.present? && !records.include?(normalized_dns_value(host, host.dns_expected_value))
        "Expected #{host.dns_expected_value}, got #{records.first(3).join(', ')}"
      end

    Result.new(
      probe_type: :dns,
      success: error_message.nil?,
      latency: error_message.nil? ? elapsed_ms(start) : nil,
      error_message: error_message,
      metadata: { "records" => records.first(10), "elapsed_ms" => (elapsed_ms(start) if error_message) }.compact,
      recorded_at: Time.current
    )
  rescue Resolv::ResolvError, SystemCallError, IOError, SocketError => e
    message = e.message.start_with?("DNS resolv timeout") ? "Timed out after #{host.timeout_seconds} seconds" : e.message
    failed_check(:dns, message, start, e)
  end

  # Pushes are recorded as they arrive (record_push!). The scheduled check only records a
  # failure once none has arrived for an interval; nil means there is nothing to record.
  def self.probe_push(host)
    last_push = host.push_received_at || host.created_at
    return nil if last_push > Time.current - host.interval.seconds - PUSH_GRACE

    Result.new(
      probe_type: :push,
      success: false,
      error_message: host.push_received_at ? "No push received in #{host.interval} seconds" : "No push received yet",
      metadata: {},
      recorded_at: Time.current
    )
  end

  # Asks the Docker Engine API about one container, over the local socket or TCP (e.g. a
  # docker-socket-proxy). Up = running, not paused, and not unhealthy if it has a health check.
  def self.probe_docker(host)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status_code, body = docker_get(host, "/containers/#{host.address}/json", start + host.timeout_seconds)

    unless status_code == 200
      message = status_code == 404 ? "Container \"#{host.address}\" not found" : "Docker API returned HTTP #{status_code}"
      api_message = (JSON.parse(body)["message"] rescue nil) unless status_code == 404
      return failed_check(:docker, [ message, api_message ].compact.join(": "), start)
    end

    state = JSON.parse(body).fetch("State", {})
    health = state.dig("Health", "Status")
    error_message =
      if !state["Running"]
        exit_code = " (exit code #{state['ExitCode']})" if state["Status"] == "exited"
        "Container is #{state['Status'].presence || 'not running'}#{exit_code}"
      elsif state["Paused"]
        "Container is paused"
      elsif health == "unhealthy"
        "Container is unhealthy"
      end
    return failed_check(:docker, error_message, start) if error_message

    Result.new(
      probe_type: :docker,
      success: true,
      latency: elapsed_ms(start),
      metadata: { "state" => state["Status"], "health" => health }.compact,
      recorded_at: Time.current
    )
  rescue Errno::ENOENT, Errno::EACCES => e
    path = host.docker_endpoint&.second
    message = e.is_a?(Errno::ENOENT) ? "Docker socket #{path} not found; mount it into the Pingraph container" \
                                     : "No permission to use the Docker socket #{path}; see the README"
    failed_check(:docker, message, start, e)
  rescue SystemCallError, IOError, SocketError, Timeout::Error, JSON::ParserError => e
    message = e.is_a?(Timeout::Error) ? "Timed out after #{host.timeout_seconds} seconds" : e.message
    failed_check(:docker, message, start, e)
  end

  # One GET over HTTP/1.0, so the daemon closes the connection after the reply. Returns
  # [status code, body].
  def self.docker_get(host, path, deadline)
    kind, *target = host.docker_endpoint || raise(ArgumentError, "Invalid Docker host #{host.docker_host}")
    socket = kind == :unix ? Socket.unix(target.first) : Socket.tcp(*target, connect_timeout: host.timeout_seconds)
    socket.write("GET #{path} HTTP/1.0\r\nHost: docker\r\nUser-Agent: Pingraph\r\n\r\n")

    head, body = read_socket(socket, deadline).split("\r\n\r\n", 2)
    status_code = head.to_s[%r{\AHTTP/\d(?:\.\d)? (\d{3})}, 1].to_i
    body = dechunk(body.to_s) if head.to_s.match?(/^transfer-encoding:\s*chunked/i)
    [ status_code, body.to_s.force_encoding(Encoding::UTF_8) ]
  ensure
    socket&.close
  end

  # PING over the Redis protocol, after AUTH when a password is set. Also works with Valkey
  # and KeyDB; TLS isn't supported.
  def self.probe_redis(host)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    deadline = start + host.timeout_seconds

    reply = Socket.tcp(host.address, host.port, connect_timeout: host.timeout_seconds) do |socket|
      if host.basic_auth_password.present?
        auth = redis_command(socket, deadline, "AUTH", *[ host.basic_auth_user, host.basic_auth_password ].compact)
        next auth unless auth == "+OK"
      end
      redis_command(socket, deadline, "PING")
    end
    return failed_check(:redis, redis_error_message(reply), start) unless reply == "+PONG"

    Result.new(probe_type: :redis, success: true, latency: elapsed_ms(start), metadata: {}, recorded_at: Time.current)
  rescue SystemCallError, IOError, SocketError, Timeout::Error => e
    message = e.is_a?(Timeout::Error) ? "Timed out after #{host.timeout_seconds} seconds" : e.message
    failed_check(:redis, message, start, e)
  end

  # Sends one command and returns the first line of the reply ("+PONG", "-NOAUTH ...").
  def self.redis_command(socket, deadline, *args)
    socket.write("*#{args.size}\r\n" + args.map { |arg| "$#{arg.bytesize}\r\n#{arg}\r\n" }.join)
    read_socket(socket, deadline) { |buffer| buffer.include?("\r\n") }.lines.first.to_s.chomp
  end

  def self.redis_error_message(reply)
    return "Redis closed the connection" if reply.blank?

    "Redis replied: #{reply.delete_prefix('-').force_encoding(Encoding::UTF_8).scrub.truncate(200)}"
  end

  # Reads until the peer closes the connection, the block says the reply is complete, or
  # SOCKET_READ_LIMIT; raises Timeout::Error at the (monotonic) deadline.
  def self.read_socket(socket, deadline)
    buffer = String.new
    loop do
      chunk = socket.read_nonblock(16.kilobytes, exception: false)
      case chunk
      when :wait_readable
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Timeout::Error if remaining <= 0 || !socket.wait_readable(remaining)
      when nil
        return buffer
      else
        buffer << chunk
        return buffer if buffer.bytesize >= SOCKET_READ_LIMIT || (block_given? && yield(buffer))
      end
    end
  end

  def self.dechunk(body)
    decoded = String.new
    loop do
      size_line, body = body.split("\r\n", 2)
      size = size_line.to_s.to_i(16)
      break if size.zero? || body.nil?

      decoded << body.byteslice(0, size)
      body = body.byteslice((size + 2)..).to_s
    end
    decoded
  end

  def self.dns_record_value(record)
    case record
    when Resolv::DNS::Resource::IN::A, Resolv::DNS::Resource::IN::AAAA then record.address.to_s.downcase
    when Resolv::DNS::Resource::MX then record.exchange.to_s.downcase
    when Resolv::DNS::Resource::TXT then record.strings.join
    else record.name.to_s.downcase
    end
  end

  # Expected values are compared the way records are rendered: TXT exactly, names without
  # case or a trailing dot, IPv6 addresses in their short form.
  def self.normalized_dns_value(host, value)
    return value if host.dns_record_type == "TXT"

    value = value.downcase.delete_suffix(".")
    host.dns_record_type == "AAAA" && NetworkAddress.ip?(value) ? IPAddr.new(value).to_s : value
  end

  def self.failed_check(probe_type, error_message, start, error = nil)
    Result.new(
      probe_type: probe_type,
      success: false,
      error_message: error_message,
      metadata: { "error_class" => error&.class&.name, "elapsed_ms" => elapsed_ms(start) }.compact,
      recorded_at: Time.current
    )
  end

  # Status from consecutive samples, with threshold = the host's failure_threshold:
  #   threshold failures in a row               => down
  #   threshold problem samples in a row        => degraded (failed, slow or lossy)
  #   a clean sample                            => up
  #   fewer problem samples than the threshold  => unchanged (not enough evidence)
  def self.status_for(current_status, failures, issues, threshold)
    return :down if failures >= threshold
    return :degraded if issues >= threshold
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
      computed_status = status_for(current_status, failures, issues, host.failure_threshold)

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

      # Separate from the up/down state machine: a check can pass with an expiring certificate.
      expiry_alert = CertificateExpiryAlert.evaluate(host, result, computed_status)
      deliveries += NotificationDelivery.create_for!(expiry_alert) if expiry_alert
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
  private_class_method :http_request, :http_result, :redirect_uri, :json?, :persist_result!, :enqueue_notifications, :icmp_failure_result, :ping_error_message, :elapsed_ms,
    :docker_get, :redis_command, :redis_error_message, :read_socket, :dechunk, :dns_record_value, :normalized_dns_value, :failed_check
end
