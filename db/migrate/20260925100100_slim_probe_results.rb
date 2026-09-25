class SlimProbeResults < ActiveRecord::Migration[8.1]
  # probe_results is the hottest table: every insert pays for every index. Probe type is
  # immutable per host, so (host_id, recorded_at) covers the other host-scoped indexes, and
  # recorded_at makes created_at/updated_at redundant.
  def up
    remove_index :probe_results, name: "index_probe_results_on_host_id"
    remove_index :probe_results, name: "index_probe_results_on_host_probe_type_recorded_at"
    remove_index :probe_results, name: "index_probe_results_on_host_id_and_success"

    remove_column :probe_results, :created_at
    remove_column :probe_results, :updated_at

    # ICMP jitter (ping's mdev), in ms.
    add_column :probe_results, :jitter, :float
  end

  def down
    remove_column :probe_results, :jitter

    add_column :probe_results, :created_at, :datetime
    add_column :probe_results, :updated_at, :datetime
    execute "UPDATE probe_results SET created_at = recorded_at, updated_at = recorded_at"

    add_index :probe_results, [ :host_id, :success ], name: "index_probe_results_on_host_id_and_success"
    add_index :probe_results, [ :host_id, :probe_type, :recorded_at ], name: "index_probe_results_on_host_probe_type_recorded_at"
    add_index :probe_results, :host_id, name: "index_probe_results_on_host_id"
  end
end
