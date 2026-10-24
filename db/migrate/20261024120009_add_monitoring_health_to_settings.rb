class AddMonitoringHealthToSettings < ActiveRecord::Migration[8.1]
  def change
    # Written by HostPollerJob every minute; stale means probing has stopped.
    add_column :settings, :poller_heartbeat_at, :datetime
    # Optional dead man's switch (e.g. a healthchecks.io ping URL). Encrypted.
    add_column :settings, :heartbeat_url, :text
  end
end
