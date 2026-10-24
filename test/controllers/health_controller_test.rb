require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "ok without authentication while the poller is running" do
    ProbeHealth.record_poll!(30.seconds.ago)

    get health_path

    assert_response :ok
    assert_equal "ok", response.parsed_body["status"]
    assert response.parsed_body["last_poll_at"].present?
  end

  test "503 when probing has stalled" do
    ProbeHealth.record_poll!(10.minutes.ago)

    get health_path

    assert_response :service_unavailable
    assert_equal "stalled", response.parsed_body["status"]
  end
end
