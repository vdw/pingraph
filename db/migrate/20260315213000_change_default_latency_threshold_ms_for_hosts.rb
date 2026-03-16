class ChangeDefaultLatencyThresholdMsForHosts < ActiveRecord::Migration[8.1]
  def change
    change_column_default :hosts, :latency_threshold_ms, from: 200.0, to: 350.0
  end
end
