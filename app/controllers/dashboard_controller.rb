class DashboardController < ApplicationController
  def index
    @groups = Group.includes(:hosts).order(:name).all

    # Build a map of host_id => latest probe result using a SQLite-compatible subquery
    host_ids = @groups.flat_map { |g| g.hosts.map(&:id) }
    @latest_probe_results = build_latest_probe_results(host_ids)
  end

  private

  def build_latest_probe_results(host_ids)
    return {} if host_ids.blank?

    table_name = ProbeResult.table_name

    subquery = ProbeResult
      .select("host_id, MAX(recorded_at) AS max_recorded_at")
      .where(host_id: host_ids)
      .group(:host_id)

    ProbeResult
      .joins(
        "INNER JOIN (#{subquery.to_sql}) latest " \
        "ON #{table_name}.host_id = latest.host_id " \
        "AND #{table_name}.recorded_at = latest.max_recorded_at"
      )
      .index_by(&:host_id)
  end
end
