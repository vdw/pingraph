class AddPublicStatusFieldsToGroupsAndHosts < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :is_public, :boolean, default: false, null: false
    add_column :groups, :status_slug, :string
    add_column :groups, :description, :text
    add_index :groups, :status_slug, unique: true

    add_column :hosts, :latency_threshold_ms, :float, default: 200.0, null: false
  end
end
