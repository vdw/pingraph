class PingJob < ApplicationJob
  queue_as :default

  def perform(host_id)
    host = Host.find(host_id)
    PingService.execute(host)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[PingJob] Host ##{host_id} not found, skipping."
  end
end
