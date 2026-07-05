require "test_helper"

class StatusPageUptimeBucketBuilderTest < ActiveSupport::TestCase
  test "marks bucket as degraded when latency exceeds host threshold" do
    host = hosts(:one)
    host.update_columns(latency_threshold_ms: 50, updated_at: Time.current)
    host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-15 12:00:00 UTC") do
      host.probe_results.create!(
        probe_type: :icmp,
        success: true,
        latency: 120.0,
        min_latency: 100.0,
        max_latency: 140.0,
        packet_loss: 0,
        recorded_at: 10.minutes.ago
      )

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
    assert_nil StatusPage::UptimeBucketBuilder.percentage([ { sample_count: 0, healthy_count: 0 } ])
  end

  test "percentage sums healthy and total samples across buckets" do
    blocks = [
      { sample_count: 10, healthy_count: 10 },
      { sample_count: 10, healthy_count: 9 },
      { sample_count: 0, healthy_count: 0 }
    ]

    assert_equal 95.0, StatusPage::UptimeBucketBuilder.percentage(blocks)
  end
end
