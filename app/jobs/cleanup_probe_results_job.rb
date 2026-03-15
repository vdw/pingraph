class CleanupProbeResultsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1000

  def perform
    cutoff = retention_days.days.ago
    latest_ids = ProbeResult.connection.select_values(<<~SQL)
      SELECT p1.id
      FROM probe_results p1
      WHERE p1.recorded_at = (
        SELECT MAX(p2.recorded_at)
        FROM probe_results p2
        WHERE p2.host_id = p1.host_id
      )
      AND p1.id = (
        SELECT MAX(p3.id)
        FROM probe_results p3
        WHERE p3.host_id = p1.host_id
        AND p3.recorded_at = p1.recorded_at
      )
    SQL

    scope = ProbeResult.where("recorded_at < ?", cutoff)
    scope = scope.where.not(id: latest_ids) if latest_ids.any?

    scope.in_batches(of: BATCH_SIZE) { |batch| batch.delete_all }
  end

  private

  def retention_days
    Setting.current.probe_result_retention_days
  rescue ActiveRecord::ActiveRecordError
    Setting::DEFAULT_RETENTION_DAYS
  end
end
