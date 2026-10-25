require "test_helper"

# DNS, push, Docker and Redis checks. Docker and Redis talk to small local servers on a real
# socket; DNS replaces Resolv::DNS.open.
class ProbeServiceChecksTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir("probe_checks"))
  end

  teardown do
    @server_thread&.join(2)
    FileUtils.rm_rf(@dir)
  end

  # --- DNS ---

  FakeResolver = Struct.new(:records, :error, :asked, :timeouts) do
    def getresources(name, type)
      self.asked = [ name, type ]
      raise error if error

      records
    end
  end

  def with_resolver(records: [], error: nil)
    resolver = FakeResolver.new(records, error)
    config = nil
    original = Resolv::DNS.method(:open)
    Resolv::DNS.singleton_class.define_method(:open) do |given_config, &block|
      config = given_config
      block.call(resolver)
    end
    yield resolver, -> { config }
  ensure
    Resolv::DNS.singleton_class.define_method(:open, original)
  end

  def dns_host(**attrs)
    Host.new(name: "DNS", probe_type: :dns, address: "example.com", group: groups(:one), **attrs).tap(&:validate)
  end

  def a_record(address)
    Resolv::DNS::Resource::IN::A.new(address)
  end

  test "DNS passes with records and asks the configured server" do
    with_resolver(records: [ a_record("93.184.215.14") ]) do |resolver, config|
      result = ProbeService.run_probe(dns_host(dns_server: "1.1.1.1", timeout_seconds: 3))

      assert result.success
      assert result.latency
      assert_equal [ "93.184.215.14" ], result.metadata["records"]
      assert_equal [ "example.com", Resolv::DNS::Resource::IN::A ], resolver.asked
      assert_equal({ nameserver: [ "1.1.1.1" ], raise_timeout_errors: true }, config.call)
      assert_equal 3, resolver.timeouts
    end
  end

  test "DNS fails when there are no records" do
    with_resolver(records: []) do
      result = ProbeService.run_probe(dns_host)

      assert_not result.success
      assert_nil result.latency
      assert_equal "No A records found for example.com", result.error_message
    end
  end

  test "DNS compares the expected value without case or a trailing dot" do
    mx = Resolv::DNS::Resource::IN::MX.new(10, Resolv::DNS::Name.create("Mail.Example.com."))
    with_resolver(records: [ mx ]) do
      assert ProbeService.run_probe(dns_host(dns_record_type: "MX", dns_expected_value: "mail.example.com.")).success

      result = ProbeService.run_probe(dns_host(dns_record_type: "MX", dns_expected_value: "other.example.com"))
      assert_not result.success
      assert_equal "Expected other.example.com, got mail.example.com", result.error_message
    end
  end

  test "DNS matches IPv6 addresses in any notation" do
    aaaa = Resolv::DNS::Resource::IN::AAAA.new("2606:4700:4700::1111")
    with_resolver(records: [ aaaa ]) do
      assert ProbeService.run_probe(dns_host(dns_record_type: "AAAA", dns_expected_value: "2606:4700:4700:0:0:0:0:1111")).success
    end
  end

  test "a DNS timeout fails with a readable message" do
    with_resolver(error: Resolv::ResolvError.new("DNS resolv timeout: example.com")) do
      result = ProbeService.run_probe(dns_host(timeout_seconds: 2))

      assert_not result.success
      assert_equal "Timed out after 2 seconds", result.error_message
    end
  end

  # --- Push ---

  def push_host(**attrs)
    Host.create!(name: "Backups", probe_type: :push, interval: 60, group: groups(:one), **attrs)
  end

  test "a push host with a recent push records nothing at its scheduled check" do
    host = push_host
    host.update_columns(push_received_at: 30.seconds.ago)

    assert_no_difference("ProbeResult.count") { assert_nil ProbeService.execute(host) }
  end

  test "a push host fails its check once no push arrived for an interval" do
    host = push_host
    host.update_columns(push_received_at: 2.minutes.ago)

    result = assert_difference("ProbeResult.count") { ProbeService.execute(host) }
    assert_not result.success
    assert_equal "No push received in 60 seconds", result.error_message
  end

  test "a new push host gets one interval before its first check fails" do
    host = push_host
    assert_nil ProbeService.run_probe(host)

    host.update_columns(created_at: 5.minutes.ago)
    assert_equal "No push received yet", ProbeService.run_probe(host).error_message
  end

  test "record_push! saves up and down pushes" do
    host = push_host(failure_threshold: 1)

    up = ProbeService.record_push!(host, status: "up", message: " OK ", ping: "42.5")
    assert up.success
    assert_equal 42.5, up.latency
    assert_equal({ "message" => "OK" }, up.metadata)
    assert_in_delta Time.current, host.reload.push_received_at, 5
    assert host.up?

    down = ProbeService.record_push!(host, status: "DOWN", message: "", ping: "1")
    assert_not down.success
    assert_nil down.latency
    assert_equal "Reported down", down.error_message
    assert host.reload.down?
  end

  test "record_push! ignores a ping that isn't a number" do
    host = push_host

    assert_nil ProbeService.record_push!(host, ping: "fast").latency
    assert_nil ProbeService.record_push!(host, ping: "-5").latency
    assert_nil ProbeService.record_push!(host, ping: "Infinity").latency
  end

  # --- Docker ---

  def docker_host(socket_path, **attrs)
    Host.new(name: "App", probe_type: :docker, address: "nextcloud", docker_host: "unix://#{socket_path}", timeout_seconds: 2,
      group: groups(:one), **attrs).tap(&:validate)
  end

  # Serves one connection on a Unix socket: records the request and sends response.
  def docker_daemon(response)
    path = @dir.join("docker.sock")
    server = UNIXServer.new(path.to_s)
    requests = []
    @server_thread = Thread.new do
      client = server.accept
      requests << client.readpartial(4096)
      # No response: wait until Pingraph gives up and closes the connection.
      response ? client.write(response) : client.read
    ensure
      client&.close
      server.close
    end
    [ path, requests ]
  end

  def docker_response(state, status: "200 OK", headers: "")
    body = { "Id" => "abc", "State" => state }.to_json
    "HTTP/1.0 #{status}\r\nContent-Type: application/json\r\n#{headers}\r\n#{body}"
  end

  test "Docker passes for a running container and asks for it by name" do
    path, requests = docker_daemon(docker_response({ "Status" => "running", "Running" => true, "Health" => { "Status" => "healthy" } }))

    result = ProbeService.run_probe(docker_host(path))

    assert result.success, result.error_message
    assert_equal({ "state" => "running", "health" => "healthy" }, result.metadata)
    assert_match %r{\AGET /containers/nextcloud/json HTTP/1.0\r\n}, requests.first
  end

  test "Docker fails for an exited container with its exit code" do
    path, = docker_daemon(docker_response({ "Status" => "exited", "Running" => false, "ExitCode" => 137 }))

    result = ProbeService.run_probe(docker_host(path))

    assert_not result.success
    assert_equal "Container is exited (exit code 137)", result.error_message
  end

  test "Docker fails for an unhealthy or paused container" do
    path, = docker_daemon(docker_response({ "Status" => "running", "Running" => true, "Health" => { "Status" => "unhealthy" } }))
    assert_equal "Container is unhealthy", ProbeService.run_probe(docker_host(path)).error_message
    @server_thread.join

    FileUtils.rm_f(path)
    path, = docker_daemon(docker_response({ "Status" => "paused", "Running" => true, "Paused" => true }))
    assert_equal "Container is paused", ProbeService.run_probe(docker_host(path)).error_message
  end

  test "Docker reports a missing container" do
    path, = docker_daemon("HTTP/1.0 404 Not Found\r\n\r\n{\"message\":\"No such container: nextcloud\"}")

    assert_equal "Container \"nextcloud\" not found", ProbeService.run_probe(docker_host(path)).error_message
  end

  test "Docker reads chunked replies" do
    body = { "State" => { "Status" => "running", "Running" => true } }.to_json
    chunked = "#{body[0, 10].bytesize.to_s(16)}\r\n#{body[0, 10]}\r\n#{body[10..].bytesize.to_s(16)}\r\n#{body[10..]}\r\n0\r\n\r\n"
    path, = docker_daemon("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n#{chunked}")

    assert ProbeService.run_probe(docker_host(path)).success
  end

  test "Docker times out when the daemon doesn't answer" do
    path, = docker_daemon(nil)

    result = ProbeService.run_probe(docker_host(path, timeout_seconds: 1))

    assert_not result.success
    assert_equal "Timed out after 1 seconds", result.error_message
  end

  test "Docker explains a missing socket" do
    result = ProbeService.run_probe(docker_host(@dir.join("missing.sock")))

    assert_not result.success
    assert_match "not found; mount it into the Pingraph container", result.error_message
  end

  # --- Redis ---

  # Serves one connection on 127.0.0.1, answering each command with the next reply.
  def redis_server(*replies)
    server = TCPServer.new("127.0.0.1", 0)
    commands = []
    @server_thread = Thread.new do
      client = server.accept
      replies.each do |reply|
        commands << client.readpartial(4096)
        client.write("#{reply}\r\n")
      end
    ensure
      client&.close
      server.close
    end
    [ server.addr[1], commands ]
  end

  def redis_host(port, **attrs)
    Host.new(name: "Cache", probe_type: :redis, address: "127.0.0.1", port: port, timeout_seconds: 2, group: groups(:one), **attrs).tap(&:validate)
  end

  test "Redis passes on PONG" do
    port, commands = redis_server("+PONG")

    result = ProbeService.run_probe(redis_host(port))

    assert result.success
    assert result.latency
    assert_equal [ "*1\r\n$4\r\nPING\r\n" ], commands
  end

  test "Redis authenticates with a password, and a username when set" do
    port, commands = redis_server("+OK", "+PONG")
    assert ProbeService.run_probe(redis_host(port, basic_auth_password: "s3cret")).success
    assert_equal "*2\r\n$4\r\nAUTH\r\n$6\r\ns3cret\r\n", commands.first
    @server_thread.join

    port, commands = redis_server("+OK", "+PONG")
    assert ProbeService.run_probe(redis_host(port, basic_auth_user: "monitor", basic_auth_password: "s3cret")).success
    assert_equal "*3\r\n$4\r\nAUTH\r\n$7\r\nmonitor\r\n$6\r\ns3cret\r\n", commands.first
  end

  test "Redis reports the server's error" do
    port, = redis_server("-NOAUTH Authentication required.")

    result = ProbeService.run_probe(redis_host(port))

    assert_not result.success
    assert_equal "Redis replied: NOAUTH Authentication required.", result.error_message
  end

  test "Redis stops after a failed AUTH" do
    port, commands = redis_server("-WRONGPASS invalid username-password pair")

    result = ProbeService.run_probe(redis_host(port, basic_auth_password: "wrong"))

    assert_equal "Redis replied: WRONGPASS invalid username-password pair", result.error_message
    assert_equal 1, commands.size
  end
end
