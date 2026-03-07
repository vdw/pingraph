require "test_helper"

class CleanupPingsJobTest < ActiveJob::TestCase
  test "removes pings older than retention while keeping latest per host" do
    host_one = hosts(:one)
    host_two = hosts(:two)

    Ping.delete_all

    freeze_time do
      recent = host_one.pings.create!(
        latency: 5.0,
        min_latency: 4.5,
        max_latency: 6.0,
        packet_loss: 0,
        recorded_at: 10.days.ago
      )

      old_host_one = host_one.pings.create!(
        latency: 12.0,
        min_latency: 11.0,
        max_latency: 13.0,
        packet_loss: 0,
        recorded_at: 120.days.ago
      )

      old_host_two = host_two.pings.create!(
        latency: 20.0,
        min_latency: 18.0,
        max_latency: 22.0,
        packet_loss: 0,
        recorded_at: 120.days.ago
      )

      CleanupPingsJob.perform_now

      assert Ping.exists?(recent.id)
      assert_not Ping.exists?(old_host_one.id)
      assert Ping.exists?(old_host_two.id)
    end
  end
end
