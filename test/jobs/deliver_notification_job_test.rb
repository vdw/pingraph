require "test_helper"

class DeliverNotificationJobTest < ActiveJob::TestCase
  test "runs on the notifications queue" do
    assert_equal "notifications", DeliverNotificationJob.new.queue_name
  end

  test "reconstructs the payload and dispatches without enabled channels" do
    payload = NotificationPayload.new(
      host_id: 1, host_name: "H", group_name: "G",
      status: :down, event: :down, error_message: "e",
      packet_loss: nil, latency: nil, status_code: nil, host_url: nil, occurred_at: Time.current
    )

    assert_nothing_raised do
      DeliverNotificationJob.perform_now(payload.to_job_args)
    end
  end

  test "payload survives the job-args round trip" do
    original = NotificationPayload.new(
      host_id: 5, host_name: "Router", group_name: "LAN",
      status: :down, event: :down, error_message: "err",
      packet_loss: 50, latency: 12.5, status_code: 503,
      host_url: "https://pg/hosts/5", occurred_at: Time.current
    )

    restored = NotificationPayload.from_job_args(original.to_job_args)

    assert_equal "Router", restored.host_name
    assert_equal :down, restored.event
    assert_equal :down, restored.status
    assert_equal 12.5, restored.latency
    assert_equal 503, restored.status_code
    assert_in_delta original.occurred_at.to_i, restored.occurred_at.to_i, 1
  end
end
