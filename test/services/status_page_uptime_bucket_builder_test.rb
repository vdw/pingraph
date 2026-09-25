require "test_helper"

class StatusPageUptimeBucketBuilderTest < ActiveSupport::TestCase
  test "marks bucket as degraded when latency exceeds host threshold" do
    host = hosts(:one)
    host.update_columns(latency_threshold_ms: 50, updated_at: Time.current)
    host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-15 12:00:00 UTC") do
      [ 11.minutes.ago, 10.minutes.ago ].each do |recorded_at|
        host.probe_results.create!(
          probe_type: :icmp,
          success: true,
          latency: 120.0,
          min_latency: 100.0,
          max_latency: 140.0,
          packet_loss: 0,
          recorded_at: recorded_at
        )
      end

      blocks = StatusPage::UptimeBucketBuilder.for_host(host)

      assert_equal :degraded, blocks.last[:state]
    end
  end

  test "marks bucket as down after failure threshold is reached" do
    host = hosts(:one)
    host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-15 12:00:00 UTC") do
      host.probe_results.create!(probe_type: :tcp, success: false, error_message: "timeout", recorded_at: 20.minutes.ago)
      host.probe_results.create!(probe_type: :tcp, success: false, error_message: "timeout", recorded_at: 10.minutes.ago)

      blocks = StatusPage::UptimeBucketBuilder.for_host(host)

      assert_equal :down, blocks.last[:state]
    end
  end

  test "percentage is nil when there are no samples" do
    assert_nil StatusPage::UptimeBucketBuilder.percentage([])
    assert_nil StatusPage::UptimeBucketBuilder.percentage([ { monitored_seconds: 0.0, healthy_seconds: 0.0 } ])
  end

  test "percentage sums healthy and monitored time across buckets" do
    blocks = [
      { monitored_seconds: 600.0, healthy_seconds: 600.0 },
      { monitored_seconds: 600.0, healthy_seconds: 540.0 },
      { monitored_seconds: 0.0, healthy_seconds: 0.0 }
    ]

    assert_equal 95.0, StatusPage::UptimeBucketBuilder.percentage(blocks)
  end

  test "time Pingraph was not running is unmonitored, not uptime" do
    host = hosts(:one) # interval 60s
    host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-15 12:00:00 UTC") do
      # 1 hour of checks, then Pingraph stopped for the remaining 23 hours.
      60.times do |i|
        host.probe_results.create!(probe_type: :icmp, success: i >= 6, latency: 5.0, packet_loss: i >= 6 ? 0 : 100,
                                   recorded_at: 24.hours.ago + i.minutes)
      end

      blocks = StatusPage::UptimeBucketBuilder.for_host(host)

      # 6 of ~61 monitored minutes were down; the 23 silent hours do not count as up.
      assert_in_delta 90.1, StatusPage::UptimeBucketBuilder.percentage(blocks), 0.2
      assert_operator StatusPage::UptimeBucketBuilder.coverage(blocks), :<, 0.1
    end
  end
end
