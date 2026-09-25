require "test_helper"

class PerformSpeedTestJobTest < ActiveJob::TestCase
  test "marks speed test completed on success" do
    host = Host.create!(name: "Speed Target", address: "1.1.1.1", interval: 10, group: groups(:one))
    speed_test = host.speed_tests.create!(protocol: "tcp", status: :queued)

    original_execute = SpeedTestService.method(:execute)

    SpeedTestService.singleton_class.define_method(:execute, ->(_host) {
      SpeedTestService::Result.new(success?: true, bandwidth_mbps: 98.76, protocol: "tcp")
    })

    PerformSpeedTestJob.perform_now(speed_test.id)

    speed_test.reload
    assert_equal "completed", speed_test.status
    assert_equal 98.76, speed_test.bandwidth_mbps
    assert_equal "tcp", speed_test.protocol
    assert_not_nil speed_test.recorded_at
  ensure
    SpeedTestService.singleton_class.define_method(:execute, original_execute)
  end

  test "marks speed test failed with the reason on failure" do
    host = Host.create!(name: "Speed Target", address: "1.1.1.1", interval: 10, group: groups(:one))
    speed_test = host.speed_tests.create!(protocol: "tcp", status: :queued)

    original_execute = SpeedTestService.method(:execute)

    SpeedTestService.singleton_class.define_method(:execute, ->(_host) {
      SpeedTestService::Result.new(success?: false, error_message: "unable to connect to server")
    })

    assert_no_difference("SpeedTest.count") do
      PerformSpeedTestJob.perform_now(speed_test.id)
    end

    speed_test.reload
    assert_equal "failed", speed_test.status
    assert_equal "unable to connect to server", speed_test.error_message
    assert_not host.speed_test_in_progress?
  ensure
    SpeedTestService.singleton_class.define_method(:execute, original_execute)
  end

  test "marks speed test failed when the job crashes" do
    host = Host.create!(name: "Speed Target", address: "1.1.1.1", interval: 10, group: groups(:one))
    speed_test = host.speed_tests.create!(protocol: "tcp", status: :queued)

    original_execute = SpeedTestService.method(:execute)
    SpeedTestService.singleton_class.define_method(:execute, ->(_host) { raise "boom" })

    assert_raises(RuntimeError) { PerformSpeedTestJob.perform_now(speed_test.id) }

    speed_test.reload
    assert_equal "failed", speed_test.status
    assert_includes speed_test.error_message, "boom"
  ensure
    SpeedTestService.singleton_class.define_method(:execute, original_execute)
  end
end
