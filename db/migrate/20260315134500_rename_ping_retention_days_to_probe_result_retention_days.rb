class RenamePingRetentionDaysToProbeResultRetentionDays < ActiveRecord::Migration[8.1]
  def up
    rename_column :settings, :ping_retention_days, :probe_result_retention_days
  end

  def down
    rename_column :settings, :probe_result_retention_days, :ping_retention_days
  end
end
