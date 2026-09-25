class NotificationDeliveriesController < ApplicationController
  def index
    @deliveries = NotificationDelivery.includes(:host).recent.limit(200)
  end

  def retry
    delivery = NotificationDelivery.find(params[:id])

    if delivery.failed?
      delivery.retry!
      redirect_to notification_deliveries_path, notice: "Retrying #{delivery.channel.capitalize} alert for #{delivery.host_name}."
    else
      redirect_to notification_deliveries_path, alert: "Only failed deliveries can be retried."
    end
  end
end
