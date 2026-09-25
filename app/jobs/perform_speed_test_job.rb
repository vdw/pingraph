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
      speed_test.fail!(result.error_message.presence || "Speed test failed")
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[PerformSpeedTestJob] SpeedTest ##{speed_test_id} not found, skipping."
  rescue => e
    # Never leave the record "running": that would block new tests for this host.
    begin
      speed_test&.fail!("Unexpected error: #{e.message}")
    rescue ActiveRecord::ActiveRecordError
      # Keep the original error; SpeedTest.fail_stale! will clean the record up later.
    end
    raise
  end
end
