class AddFailureThresholdToHosts < ActiveRecord::Migration[8.1]
  def change
    # Checks in a row needed to turn Down (failures) or Degraded (problems). 2 was fixed before.
    add_column :hosts, :failure_threshold, :integer, default: 2, null: false
  end
end
