class CreatePings < ActiveRecord::Migration[8.1]
  def change
    create_table :pings do |t|
      t.references :host, null: false, foreign_key: true
      t.float :latency
      t.float :min_latency
      t.float :max_latency
      t.integer :packet_loss
      t.datetime :recorded_at

      t.timestamps
    end

    add_index :pings, :recorded_at
    add_index :pings, [ :host_id, :recorded_at ]
  end
end
