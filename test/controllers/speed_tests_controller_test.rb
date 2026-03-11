require "test_helper"

class SpeedTestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @host = hosts(:two)
    @host.update!(address: "8.8.8.8", interval: 10)
    @host.speed_tests.delete_all
    clear_enqueued_jobs
  end

  test "should get index" do
    get speed_tests_url
    assert_response :success
  end

  test "should enqueue speed test from turbo stream request" do
    assert_difference("SpeedTest.count", +1) do
      assert_enqueued_with(job: PerformSpeedTestJob) do
        post run_speed_tests_url(format: :turbo_stream), params: { host_id: @host.id }
      end
    end

    assert_response :success
  end

  test "should not enqueue duplicate speed test while one is in progress" do
    @host.speed_tests.create!(protocol: "tcp", status: :queued)

    assert_no_difference("SpeedTest.count") do
      post run_speed_tests_url(format: :turbo_stream), params: { host_id: @host.id }
    end

    assert_response :success
  end

  test "should render panel as turbo stream" do
    get panel_speed_tests_url(format: :turbo_stream), params: { host_id: @host.id }
    assert_response :success
  end
end
