class CleanupPingsJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 90
  BATCH_SIZE = 1000

  def perform
    cutoff = RETENTION_DAYS.days.ago
    latest_ids = Ping.connection.select_values(<<~SQL)
      SELECT p1.id
      FROM pings p1
      WHERE p1.recorded_at = (
        SELECT MAX(p2.recorded_at)
        FROM pings p2
        WHERE p2.host_id = p1.host_id
      )
      AND p1.id = (
        SELECT MAX(p3.id)
        FROM pings p3
        WHERE p3.host_id = p1.host_id
        AND p3.recorded_at = p1.recorded_at
      )
    SQL

    scope = Ping.where("recorded_at < ?", cutoff)
    scope = scope.where.not(id: latest_ids) if latest_ids.any?

    scope.in_batches(of: BATCH_SIZE) { |batch| batch.delete_all }
  end
end
