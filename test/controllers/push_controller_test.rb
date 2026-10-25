require "test_helper"

class PushControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create!(name: "Backups", probe_type: :push, interval: 90_000, failure_threshold: 1, group: groups(:one))
  end

  test "a GET push records an up result without signing in" do
    assert_difference("@host.probe_results.count") do
      get push_path(@host.push_token), params: { msg: "OK", ping: "12" }
    end

    assert_response :success
    assert_equal({ "ok" => true }, response.parsed_body)
    result = @host.probe_results.last
    assert result.success
    assert_equal 12.0, result.latency
    assert @host.reload.up?
  end

  test "a POST push can report the job failed" do
    post push_path(@host.push_token), params: { status: "down", msg: "Backup failed" }

    assert_response :success
    assert @host.reload.down?
    assert_equal "Backup failed", @host.last_error_message
  end

  test "an unknown token is a 404" do
    assert_no_difference("ProbeResult.count") { get push_path("nope") }

    assert_response :not_found
    assert_equal false, response.parsed_body["ok"]
  end
end
