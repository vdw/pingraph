class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.integer :ping_retention_days, null: false, default: 90

      t.timestamps
    end
  end
end
