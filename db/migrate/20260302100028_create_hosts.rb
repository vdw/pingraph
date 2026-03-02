class CreateHosts < ActiveRecord::Migration[8.1]
  def change
    create_table :hosts do |t|
      t.string :name
      t.string :address
      t.integer :interval, default: 60, null: false
      t.references :group, null: false, foreign_key: true

      t.timestamps
    end
  end
end
