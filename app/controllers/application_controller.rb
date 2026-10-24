class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :failed_notification_delivery, :probe_health_warning

  private

  # Shown as a banner on every page until a later alert is delivered successfully.
  def failed_notification_delivery
    return @failed_notification_delivery if defined?(@failed_notification_delivery)

    @failed_notification_delivery = authenticated? ? NotificationDelivery.latest_failure : nil
  end

  # :stalled when checks have stopped, :falling_behind when they keep running late.
  def probe_health_warning
    return @probe_health_warning if defined?(@probe_health_warning)

    @probe_health_warning =
      if authenticated?
        if ProbeHealth.stalled?
          :stalled
        elsif ProbeHealth.falling_behind?
          :falling_behind
        end
      end
  end
end
