require "test_helper"

class SpeedTestTest < ActiveSupport::TestCase
  test "tests stuck in progress are failed so they stop blocking the host" do
    host = hosts(:one)
    host.speed_tests.delete_all
    stuck = host.speed_tests.create!(protocol: "tcp", status: :running)
    stuck.update_columns(updated_at: 10.minutes.ago)
    fresh = host.speed_tests.create!(protocol: "tcp", status: :queued)

    assert host.speed_test_in_progress?
    SpeedTest.fail_stale!

    assert stuck.reload.failed?
    assert_includes stuck.error_message, "Timed out"
    assert fresh.reload.queued?
  end

  test "a stuck test does not count as in progress" do
    host = hosts(:one)
    host.speed_tests.delete_all
    host.speed_tests.create!(protocol: "tcp", status: :running).update_columns(updated_at: 10.minutes.ago)

    assert_not host.speed_test_in_progress?
  end
end
