require "test_helper"

class DeliverNotificationJobTest < ActiveJob::TestCase
  setup do
    Setting.current.update_columns(slack_enabled: true, slack_webhook_url: "https://hooks.slack.com/services/x", base_url: "https://pg.test")
    @payload = NotificationPayload.new(
      host_id: hosts(:one).id, host_name: "Router", group_name: "LAN",
      status: :down, event: :down, error_message: "100% packet loss",
      packet_loss: 100, latency: nil, status_code: nil, host_url: "https://pg.test/hosts/1", occurred_at: Time.current
    )
    @delivery = NotificationDelivery.create_for!(@payload).first
  end

  def stub_slack(behaviour)
    original = NotificationChannels::Slack.instance_method(:deliver)
    NotificationChannels::Slack.define_method(:deliver, &behaviour)
    yield
  ensure
    NotificationChannels::Slack.define_method(:deliver, original)
  end

  test "runs on the notifications queue" do
    assert_equal "notifications", DeliverNotificationJob.new.queue_name
  end

  test "marks the delivery sent on success" do
    stub_slack(->(_payload) { :ok }) do
      DeliverNotificationJob.perform_now(@delivery.id)
    end

    @delivery.reload
    assert @delivery.sent?
    assert_equal 1, @delivery.attempts
    assert_not_nil @delivery.delivered_at
  end

  test "a failed attempt records the error and schedules a retry instead of losing the alert" do
    stub_slack(->(_payload) { raise NotificationChannels::Base::DeliveryError, "Slack webhook responded 500" }) do
      assert_enqueued_with(job: DeliverNotificationJob, args: [ @delivery.id ]) do
        DeliverNotificationJob.perform_now(@delivery.id)
      end
    end

    @delivery.reload
    assert @delivery.pending?
    assert_equal 1, @delivery.attempts
    assert_includes @delivery.error_message, "Slack webhook responded 500"
  end

  test "gives up after the last attempt and marks the delivery failed" do
    stub_slack(->(_payload) { raise NotificationChannels::Base::DeliveryError, "Slack webhook responded 500" }) do
      job = DeliverNotificationJob.new(@delivery.id)
      # retry_on counts attempts per exception class.
      job.exception_executions = { "[StandardError]" => DeliverNotificationJob::MAX_ATTEMPTS - 1 }

      assert_no_enqueued_jobs(only: DeliverNotificationJob) { job.perform_now }
    end

    @delivery.reload
    assert @delivery.failed?
    assert_includes @delivery.error_message, "500"
    assert_equal @delivery, NotificationDelivery.latest_failure
  end

  test "never re-sends a delivery that already went out" do
    @delivery.update!(status: :sent)

    stub_slack(->(_payload) { raise "must not be called" }) do
      DeliverNotificationJob.perform_now(@delivery.id)
    end

    assert @delivery.reload.sent?
    assert_equal 0, @delivery.attempts
  end

  test "a channel disabled before delivery is marked failed without retrying" do
    Setting.current.update_columns(slack_enabled: false)

    assert_no_enqueued_jobs(only: DeliverNotificationJob) do
      DeliverNotificationJob.perform_now(@delivery.id)
    end
    assert @delivery.reload.failed?
  end

  test "still delivers jobs enqueued before deliveries were tracked" do
    delivered = []
    stub_slack(->(payload) { delivered << payload.host_name; :ok }) do
      DeliverNotificationJob.perform_now(@payload.to_job_args)
    end

    assert_equal [ "Router" ], delivered
  end

  test "payload survives the job-args round trip" do
    restored = NotificationPayload.from_job_args(@payload.to_job_args)

    assert_equal "Router", restored.host_name
    assert_equal :down, restored.event
    assert_equal :down, restored.status
    assert_equal 100, restored.packet_loss
    assert_in_delta @payload.occurred_at.to_i, restored.occurred_at.to_i, 1
  end

  test "a later successful delivery clears the failure warning" do
    @delivery.update!(status: :failed)
    assert_equal @delivery, NotificationDelivery.latest_failure

    NotificationDelivery.create_for!(@payload).first.update!(status: :sent)
    assert_nil NotificationDelivery.latest_failure
  end
end
