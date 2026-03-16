require "test_helper"

class StatusPageIncidentBuilderTest < ActiveSupport::TestCase
  test "builds incidents from degraded and down sequences" do
    host = hosts(:one)
    host.update_columns(latency_threshold_ms: 50, updated_at: Time.current)
    host.probe_results.delete_all

    travel_to Time.zone.parse("2026-03-15 12:00:00 UTC") do
      host.probe_results.create!(probe_type: :icmp, success: true, latency: 120.0, min_latency: 110.0, max_latency: 130.0, packet_loss: 0, recorded_at: 90.minutes.ago)
      host.probe_results.create!(probe_type: :icmp, success: true, latency: 20.0, min_latency: 19.0, max_latency: 21.0, packet_loss: 0, recorded_at: 80.minutes.ago)
      host.probe_results.create!(probe_type: :tcp, success: false, error_message: "connection refused", recorded_at: 60.minutes.ago)
      host.probe_results.create!(probe_type: :tcp, success: false, error_message: "connection refused", recorded_at: 50.minutes.ago)
      host.probe_results.create!(probe_type: :tcp, success: true, latency: 5.0, recorded_at: 40.minutes.ago)

      incidents = StatusPage::IncidentBuilder.call([ host ])

      assert_equal 2, incidents.size
      assert_equal :down, incidents.first.state
      assert_equal :degraded, incidents.last.state
    end
  end
end
