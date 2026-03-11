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

  test "should destroy host" do
    assert_difference("Host.count", -1) do
      delete host_url(@host)
    end

    assert_redirected_to hosts_url
  end

  test "pings_data defaults to 24h window" do
    @host.pings.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.pings.create!(recorded_at: 30.hours.ago, latency: 9.0, min_latency: 9.0, max_latency: 9.0, packet_loss: 0)
      @host.pings.create!(recorded_at: 2.hours.ago, latency: 11.0, min_latency: 10.0, max_latency: 12.0, packet_loss: 0)

      get pings_data_host_url(@host), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal 1, body.size
      assert_in_delta 11.0, body.first.fetch("latency"), 0.01
    end
  end

  test "pings_data auto mode downsamples for 7d" do
    @host.pings.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.pings.create!(recorded_at: 6.days.ago + 10.minutes, latency: 10.0, min_latency: 8.0, max_latency: 13.0, packet_loss: 0)
      @host.pings.create!(recorded_at: 6.days.ago + 20.minutes, latency: 30.0, min_latency: 7.0, max_latency: 40.0, packet_loss: 15)
      @host.pings.create!(recorded_at: 6.days.ago + 55.minutes, latency: 20.0, min_latency: 19.0, max_latency: 21.0, packet_loss: 5)

      get pings_data_host_url(@host, window: "7d", resolution: "auto"), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal 2, body.size
      assert_in_delta 20.0, body.first.fetch("latency"), 0.01
      assert_in_delta 7.0, body.first.fetch("min_latency"), 0.01
      assert_in_delta 40.0, body.first.fetch("max_latency"), 0.01
      assert_equal 15, body.first.fetch("packet_loss")
    end
  end

  test "pings_data manual raw override bypasses downsampling" do
    @host.pings.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.pings.create!(recorded_at: 2.hours.ago + 1.minute, latency: 10.0, min_latency: 9.0, max_latency: 12.0, packet_loss: 0)
      @host.pings.create!(recorded_at: 2.hours.ago + 2.minutes, latency: 20.0, min_latency: 19.0, max_latency: 22.0, packet_loss: 0)

      get pings_data_host_url(@host, window: "24h", resolution: "raw"), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal 2, body.size
    end
  end

  test "pings_data keeps stable keys and supports null latencies" do
    @host.pings.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      @host.pings.create!(recorded_at: 1.hour.ago, latency: nil, min_latency: nil, max_latency: nil, packet_loss: 100)

      get pings_data_host_url(@host, window: "3h", resolution: "raw"), as: :json
      assert_response :success

      body = JSON.parse(response.body)
      keys = body.first.keys.sort
      assert_equal %w[latency max_latency min_latency packet_loss recorded_at], keys
      assert_nil body.first.fetch("latency")
      assert_equal 100, body.first.fetch("packet_loss")
    end
  end

  test "pings_data returns empty array when selected window has no probes" do
    @host.pings.delete_all

    get pings_data_host_url(@host, window: "3h", resolution: "auto"), as: :json
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end
end
