class RenamePingsToProbeResults < ActiveRecord::Migration[8.1]
  def up
    rename_table :pings, :probe_results

    rename_index_if_exists :probe_results, "index_pings_on_host_id", "index_probe_results_on_host_id"
    rename_index_if_exists :probe_results, "index_pings_on_recorded_at", "index_probe_results_on_recorded_at"
    rename_index_if_exists :probe_results, "index_pings_on_host_id_and_recorded_at", "index_probe_results_on_host_id_and_recorded_at"
    rename_index_if_exists :probe_results, "index_pings_on_host_probe_type_recorded_at", "index_probe_results_on_host_probe_type_recorded_at"
  end

  def down
    rename_index_if_exists :probe_results, "index_probe_results_on_host_id", "index_pings_on_host_id"
    rename_index_if_exists :probe_results, "index_probe_results_on_recorded_at", "index_pings_on_recorded_at"
    rename_index_if_exists :probe_results, "index_probe_results_on_host_id_and_recorded_at", "index_pings_on_host_id_and_recorded_at"
    rename_index_if_exists :probe_results, "index_probe_results_on_host_probe_type_recorded_at", "index_pings_on_host_probe_type_recorded_at"

    rename_table :probe_results, :pings
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    return unless index_name_exists?(table_name, old_name)

    rename_index table_name, old_name, new_name
  end
end
