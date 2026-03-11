require "test_helper"

class PingTest < ActiveSupport::TestCase
  test "downsampled_for_range aggregates by bucket in ascending order" do
    host = hosts(:one)
    host.pings.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      host.pings.create!(recorded_at: Time.zone.parse("2026-03-11 11:01:00 UTC"), latency: 10.0, min_latency: 8.0, max_latency: 15.0, packet_loss: 0)
      host.pings.create!(recorded_at: Time.zone.parse("2026-03-11 11:04:00 UTC"), latency: 30.0, min_latency: 6.0, max_latency: 40.0, packet_loss: 20)
      host.pings.create!(recorded_at: Time.zone.parse("2026-03-11 11:11:00 UTC"), latency: 25.0, min_latency: 20.0, max_latency: 30.0, packet_loss: 5)

      rows = host.pings.downsampled_for_range(Time.current - 1.hour, 10).to_a

      assert_equal 2, rows.size
      assert_operator rows.first.bucket_epoch.to_i, :<, rows.last.bucket_epoch.to_i

      first_bucket = rows.first
      assert_in_delta 20.0, first_bucket.latency.to_f, 0.01
      assert_in_delta 6.0, first_bucket.min_latency.to_f, 0.01
      assert_in_delta 40.0, first_bucket.max_latency.to_f, 0.01
      assert_equal 20, first_bucket.packet_loss

      second_bucket = rows.last
      assert_in_delta 25.0, second_bucket.latency.to_f, 0.01
      assert_in_delta 20.0, second_bucket.min_latency.to_f, 0.01
      assert_in_delta 30.0, second_bucket.max_latency.to_f, 0.01
      assert_equal 5, second_bucket.packet_loss
    end
  end

  test "downsampled_for_range keeps null rtt values while tracking packet loss" do
    host = hosts(:one)
    host.pings.delete_all

    travel_to Time.zone.parse("2026-03-11 12:00:00 UTC") do
      host.pings.create!(recorded_at: Time.current - 5.minutes, latency: nil, min_latency: nil, max_latency: nil, packet_loss: 100)

      row = host.pings.downsampled_for_range(Time.current - 1.hour, 5).first

      assert_nil row.latency
      assert_nil row.min_latency
      assert_nil row.max_latency
      assert_equal 100, row.packet_loss
    end
  end
end
