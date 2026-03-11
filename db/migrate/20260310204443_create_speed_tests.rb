class CreateSpeedTests < ActiveRecord::Migration[8.1]
  def change
    create_table :speed_tests do |t|
      t.references :host, null: false, foreign_key: true
      t.float :bandwidth_mbps
      t.string :protocol, null: false, default: "tcp"
      t.datetime :recorded_at
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :speed_tests, :recorded_at
    add_index :speed_tests, :status
    add_index :speed_tests, [ :host_id, :recorded_at ]
  end
end
