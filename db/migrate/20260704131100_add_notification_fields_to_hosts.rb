class AddNotificationFieldsToHosts < ActiveRecord::Migration[8.1]
  def up
    add_column :hosts, :notifications_enabled, :boolean, default: true, null: false
    add_column :hosts, :notify_on_degraded, :boolean, default: false, null: false
    # Mirrors the Host status enum (unknown/up/degraded/down). Tracks the last state the
    # user was actually notified about — the baseline for alert de-duplication.
    add_column :hosts, :last_notified_status, :integer, default: 0, null: false

    # Seed the baseline from each host's current status so that enabling notifications
    # does not fire an alert storm for hosts that are already down/degraded.
    execute "UPDATE hosts SET last_notified_status = status"
  end

  def down
    remove_column :hosts, :last_notified_status
    remove_column :hosts, :notify_on_degraded
    remove_column :hosts, :notifications_enabled
  end
end
