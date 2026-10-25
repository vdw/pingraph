require "test_helper"

class HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @host = hosts(:one)
    @host.update!(address: "1.1.1.1", interval: 10)
  end

  test "should get index" do
    get hosts_url
    assert_response :success
  end

  test "should get new" do
    get new_host_url
    assert_response :success
  end

  test "should create host" do
    assert_difference("Host.count") do
      post hosts_url, params: { host: { address: "example.local", group_id: @host.group_id, interval: 10, name: "Example Host" } }
    end

    assert_redirected_to host_url(Host.last)
  end

  test "should show host" do
    get host_url(@host)
    assert_response :success
  end

  test "should get edit" do
    get edit_host_url(@host)
    assert_response :success
  end

  test "should update host" do
    patch host_url(@host), params: { host: { address: "updated.example.local", group_id: @host.group_id, interval: 10, name: "Updated Host" } }
    assert_redirected_to host_url(@host)
  end

  test "creates an http host with request options and keeps its password on a blank update" do
    assert_difference("Host.count") do
      post hosts_url, params: { host: {
        name: "API", address: "https://api.test/health", group_id: @host.group_id, interval: 60, probe_type: "http",
        http_method: "POST", request_body: "{}", request_headers: "X-Key: 1", keyword: "ok", max_redirects: 3,
        timeout_seconds: 15, basic_auth_user: "admin", basic_auth_password: "s3cret", ssl_expiry_warn_days: ""
      } }
    end

    host = Host.order(:id).last
    assert_equal [ "POST", 3, 15, "ok", nil ], [ host.http_method, host.max_redirects, host.timeout_seconds, host.keyword, host.ssl_expiry_warn_days ]

    patch host_url(host), params: { host: { name: "API v2", basic_auth_user: "admin", basic_auth_password: "" } }
    assert_redirected_to host_url(host)
    assert_equal "s3cret", host.reload.basic_auth_password

    host.update_columns(ssl_expires_at: 5.days.from_now)
    get host_url(host)
    assert_response :success
    assert_match "Certificate expires", response.body

    get edit_host_url(host)
    assert_response :success
    assert_select "textarea[name='host[request_headers]']", text: "X-Key: 1"
    assert_select "input[name='host[basic_auth_password]'][value]", count: 0
  end

  test "should destroy host" do
    assert_difference("Host.count", -1) do
      delete host_url(@host)
    end

    assert_redirected_to hosts_url
  end

  test "probe_results_data defaults to 24h window" do
    @host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.probe_results.create!(probe_type: :icmp, success: true, recorded_at: 30.hours.ago, latency: 9.0, min_latency: 9.0, max_latency: 9.0, packet_loss: 0)
      @host.probe_results.create!(probe_type: :icmp, success: true, recorded_at: 2.hours.ago, latency: 11.0, min_latency: 10.0, max_latency: 12.0, packet_loss: 0)

      get probe_results_data_host_url(@host), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal 1, body.size
      assert_in_delta 11.0, body.first.fetch("latency"), 0.01
    end
  end

  test "probe_results_data auto mode downsamples for 7d" do
    @host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.probe_results.create!(probe_type: :icmp, success: true, recorded_at: 6.days.ago + 10.minutes, latency: 10.0, min_latency: 8.0, max_latency: 13.0, packet_loss: 0)
      @host.probe_results.create!(probe_type: :icmp, success: true, recorded_at: 6.days.ago + 20.minutes, latency: 30.0, min_latency: 7.0, max_latency: 40.0, packet_loss: 15)
      @host.probe_results.create!(probe_type: :icmp, success: true, recorded_at: 6.days.ago + 55.minutes, latency: 20.0, min_latency: 19.0, max_latency: 21.0, packet_loss: 5)

      get probe_results_data_host_url(@host, window: "7d", resolution: "auto"), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal 2, body.size
      assert_in_delta 20.0, body.first.fetch("latency"), 0.01
      assert_in_delta 7.0, body.first.fetch("min_latency"), 0.01
      assert_in_delta 40.0, body.first.fetch("max_latency"), 0.01
      assert_equal 15, body.first.fetch("packet_loss")
    end
  end

  test "probe_results_data manual raw override bypasses downsampling" do
    @host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.probe_results.create!(probe_type: :icmp, success: true, recorded_at: 2.hours.ago + 1.minute, latency: 10.0, min_latency: 9.0, max_latency: 12.0, packet_loss: 0)
      @host.probe_results.create!(probe_type: :icmp, success: true, recorded_at: 2.hours.ago + 2.minutes, latency: 20.0, min_latency: 19.0, max_latency: 22.0, packet_loss: 0)

      get probe_results_data_host_url(@host, window: "24h", resolution: "raw"), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal 2, body.size
    end
  end

  test "probe_results_data keeps stable keys and supports null latencies" do
    @host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.probe_results.create!(probe_type: :icmp, success: false, recorded_at: 1.hour.ago, latency: nil, min_latency: nil, max_latency: nil, packet_loss: 100)

      get probe_results_data_host_url(@host, window: "3h", resolution: "raw"), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      keys = body.first.keys.sort
      assert_equal %w[error_message jitter latency max_latency min_latency packet_loss probe_type recorded_at status_code success], keys
      assert_nil body.first.fetch("latency")
      assert_equal 100, body.first.fetch("packet_loss")
      assert_equal "icmp", body.first.fetch("probe_type")
      assert_equal false, body.first.fetch("success")
    end
  end

  test "probe_results_data returns empty array when selected window has no probes" do
    @host.probe_results.delete_all

    get probe_results_data_host_url(@host, window: "3h", resolution: "auto"), as: :json
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test "dashboard warns when hosts are not being checked" do
    Setting.current.update_columns(poller_heartbeat_at: 10.minutes.ago)

    get root_url

    assert_response :success
    assert_includes response.body, "Hosts are not being checked"
  end

  test "dashboard has no probing warning while the poller runs" do
    ProbeHealth.record_poll!

    get root_url

    assert_response :success
    assert_not_includes response.body, "Hosts are not being checked"
  end

  test "creates a push host and shows its push URL" do
    assert_difference("Host.count") do
      post hosts_url, params: { host: { name: "Nightly backup", probe_type: "push", address: "", interval: 90_000, group_id: groups(:one).id } }
    end

    host = Host.last
    assert host.push?
    follow_redirect!
    assert_response :success
    assert_includes response.body, "/api/push/#{host.push_token}"
  end

  test "the push URL uses the Base URL from Settings" do
    Setting.current.update_columns(base_url: "https://pingraph.example.com")
    host = Host.create!(name: "Backups", probe_type: :push, interval: 60, group: groups(:one))

    get host_url(host)

    assert_includes response.body, "https://pingraph.example.com/api/push/#{host.push_token}"
  end

  test "regenerates a push token" do
    host = Host.create!(name: "Backups", probe_type: :push, interval: 60, group: groups(:one))
    old_token = host.push_token

    post regenerate_push_token_host_url(host)

    assert_redirected_to host_url(host)
    assert_not_equal old_token, host.reload.push_token
  end

  test "creates DNS, Docker and Redis hosts" do
    post hosts_url, params: { host: { name: "Pi-hole", probe_type: "dns", address: "nas.lan", dns_server: "192.168.1.2",
      dns_record_type: "A", dns_expected_value: "192.168.1.10", interval: 60, group_id: groups(:one).id } }
    assert_equal [ "192.168.1.2", "A", "192.168.1.10" ], Host.last.slice(:dns_server, :dns_record_type, :dns_expected_value).values

    post hosts_url, params: { host: { name: "Nextcloud", probe_type: "docker", address: "nextcloud", docker_host: "tcp://proxy:2375",
      interval: 60, group_id: groups(:one).id } }
    assert_equal "tcp://proxy:2375", Host.last.docker_host

    post hosts_url, params: { host: { name: "Redis", probe_type: "redis", address: "10.0.0.5", port: "", basic_auth_user: "",
      basic_auth_password: "s3cret", interval: 60, group_id: groups(:one).id } }
    assert_equal [ 6379, "s3cret" ], [ Host.last.port, Host.last.basic_auth_password ]
  end

  test "host pages and the dashboard show results of every probe type" do
    group = groups(:one)
    hosts = [
      Host.create!(name: "DNS", probe_type: :dns, address: "example.com", group: group),
      Host.create!(name: "Push", probe_type: :push, interval: 60, group: group),
      Host.create!(name: "Docker", probe_type: :docker, address: "nextcloud", group: group),
      Host.create!(name: "Redis", probe_type: :redis, address: "10.0.0.5", group: group)
    ]
    metadata = { "dns" => { "records" => [ "93.184.215.14" ] }, "push" => { "message" => "Backup OK" }, "docker" => { "state" => "running" }, "redis" => {} }
    hosts.each do |host|
      host.probe_results.create!(probe_type: host.probe_type, success: true, latency: 3.0, recorded_at: Time.current, metadata: metadata.fetch(host.probe_type).to_json)
    end

    get root_url
    assert_response :success
    [ "93.184.215.14", "Backup OK", "Running", "PONG" ].each { |summary| assert_includes response.body, summary }

    hosts.each do |host|
      get host_url(host)
      assert_response :success
      get edit_host_url(host)
      assert_response :success
    end
  end
end
