class AddSchedulingFieldsToHosts < ActiveRecord::Migration[8.1]
  def change
    # The poller schedules probes on exact slots from this timestamp instead of re-deriving
    # "is it due?" from the last result's finish time (which drifted by up to a full minute).
    add_column :hosts, :next_probe_at, :datetime
    add_index :hosts, :next_probe_at

    # Consecutive "bad" samples (failed, slow or lossy). A host only turns Degraded after
    # several in a row, so one dropped packet no longer flips it.
    add_column :hosts, :consecutive_issues, :integer, default: 0, null: false
  end
end
