class DashboardController < ApplicationController
  def index
    @groups = Group.includes(:hosts).order(:name).all

    # Build a map of host_id => latest Ping using a SQLite-compatible subquery
    host_ids = @groups.flat_map { |g| g.hosts.map(&:id) }
    @latest_pings = build_latest_pings(host_ids)
  end

  private

  def build_latest_pings(host_ids)
    return {} if host_ids.blank?

    subquery = Ping
      .select("host_id, MAX(recorded_at) AS max_recorded_at")
      .where(host_id: host_ids)
      .group(:host_id)

    Ping
      .joins(
        "INNER JOIN (#{subquery.to_sql}) latest " \
        "ON pings.host_id = latest.host_id " \
        "AND pings.recorded_at = latest.max_recorded_at"
      )
      .index_by(&:host_id)
  end
end
