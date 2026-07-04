class AddMissingIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :hosts, [:group_id, :name], name: "index_hosts_on_group_id_and_name"
    add_index :probe_results, [:host_id, :success], name: "index_probe_results_on_host_id_and_success"
    add_index :speed_tests, [:host_id, :status], name: "index_speed_tests_on_host_id_and_status"
    add_index :hosts, [:group_id, :status], name: "index_hosts_on_group_id_and_status"
  end
end
