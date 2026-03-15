class ProbeJob < ApplicationJob
  queue_as :default

  def perform(host_id)
    host = Host.find(host_id)
    ProbeService.execute(host)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ProbeJob] Host ##{host_id} not found, skipping."
  end
end
