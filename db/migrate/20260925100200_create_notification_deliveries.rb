class CreateNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    # One row per (alert, channel). Lets each channel retry on its own without re-sending
    # to channels that already succeeded, and gives the UI a delivery log.
    create_table :notification_deliveries do |t|
      t.references :host, foreign_key: { on_delete: :nullify }
      t.string :channel, null: false
      t.string :event, null: false
      t.integer :status, default: 0, null: false
      t.integer :attempts, default: 0, null: false
      t.text :payload, null: false
      t.text :error_message
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :notification_deliveries, :created_at
    add_index :notification_deliveries, [ :status, :created_at ]
  end
end
