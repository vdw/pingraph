class AddProbeTypesAndHostProbeSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :hosts, :probe_type, :integer, default: 0, null: false
    add_column :hosts, :port, :integer
    add_column :hosts, :expected_status_code, :integer, default: 200, null: false
    add_column :hosts, :expected_status_code_range, :string, default: "exact", null: false
    add_column :hosts, :verify_ssl, :boolean, default: true, null: false
    add_column :hosts, :status, :integer, default: 0, null: false
    add_column :hosts, :last_probed_at, :datetime
    add_column :hosts, :last_error_message, :string
    add_column :hosts, :consecutive_failures, :integer, default: 0, null: false

    add_column :pings, :probe_type, :integer, default: 0, null: false
    add_column :pings, :success, :boolean, default: true, null: false
    add_column :pings, :status_code, :integer
    add_column :pings, :error_message, :string
    add_column :pings, :metadata, :text

    add_index :pings, [ :host_id, :probe_type, :recorded_at ], name: "index_pings_on_host_probe_type_recorded_at"

    execute <<~SQL
      UPDATE pings
      SET success = CASE WHEN packet_loss IS NULL THEN 0 WHEN packet_loss < 100 THEN 1 ELSE 0 END
    SQL
  end

  def down
    remove_index :pings, name: "index_pings_on_host_probe_type_recorded_at"

    remove_column :pings, :metadata
    remove_column :pings, :error_message
    remove_column :pings, :status_code
    remove_column :pings, :success
    remove_column :pings, :probe_type

    remove_column :hosts, :consecutive_failures
    remove_column :hosts, :last_error_message
    remove_column :hosts, :last_probed_at
    remove_column :hosts, :status
    remove_column :hosts, :verify_ssl
    remove_column :hosts, :expected_status_code_range
    remove_column :hosts, :expected_status_code
    remove_column :hosts, :port
    remove_column :hosts, :probe_type
  end
end
