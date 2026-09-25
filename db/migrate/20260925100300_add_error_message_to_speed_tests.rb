class AddErrorMessageToSpeedTests < ActiveRecord::Migration[8.1]
  def change
    add_column :speed_tests, :error_message, :text
  end
end
