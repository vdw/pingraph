class PerformSpeedTestJob < ApplicationJob
  queue_as :default

  def perform(speed_test_id)
    speed_test = SpeedTest.includes(:host).find(speed_test_id)
    speed_test.running!

    result = SpeedTestService.execute(speed_test.host)

    if result.success?
      speed_test.update!(
        status: :completed,
        bandwidth_mbps: result.bandwidth_mbps,
        protocol: result.protocol,
        recorded_at: Time.current
      )
    else
      speed_test.destroy!
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[PerformSpeedTestJob] SpeedTest ##{speed_test_id} not found, skipping."
  end
end
