require "test_helper"

class NotificationDeliveriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @delivery = NotificationDelivery.create!(
      host: hosts(:one), channel: "slack", event: "down", status: :failed, attempts: 5,
      error_message: "Slack webhook responded 500",
      payload: { "host_name" => hosts(:one).name, "event" => "down", "status" => "down" }
    )
  end

  test "lists deliveries with their errors" do
    get notification_deliveries_url

    assert_response :success
    assert_includes response.body, "Slack webhook responded 500"
    assert_includes response.body, hosts(:one).name
  end

  test "every page warns when the last alert could not be delivered" do
    get root_url

    assert_response :success
    assert_includes response.body, "Alerts are not being delivered"
  end

  test "retrying a failed delivery queues it again" do
    assert_enqueued_with(job: DeliverNotificationJob, args: [ @delivery.id ]) do
      post retry_notification_delivery_url(@delivery)
    end

    assert_redirected_to notification_deliveries_url
    assert @delivery.reload.pending?
  end

  test "requires sign in" do
    sign_out
    get notification_deliveries_url

    assert_redirected_to new_session_url
  end
end
