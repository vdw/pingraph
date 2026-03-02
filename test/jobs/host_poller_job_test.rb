require "test_helper"

class HostPollerJobTest < ActiveJob::TestCase
  test "enqueues due host with bounded jitter" do
    host = hosts(:one)
    host.update!(interval: 10)
    host.pings.delete_all

    clear_enqueued_jobs

    freeze_time do
      now = Time.current

      HostPollerJob.perform_now

      matching_jobs = enqueued_jobs.select do |job|
        job[:job] == PingJob && job[:args] == [ host.id ]
      end

      assert_equal 1, matching_jobs.size

      scheduled_at = Time.at(matching_jobs.first[:at])
      assert_operator scheduled_at, :>=, now
      assert_operator scheduled_at, :<=, now + HostPollerJob::JITTER_MAX_SECONDS.seconds
    end
  end
end
