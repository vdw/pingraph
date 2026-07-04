module Public
  class StatusController < ApplicationController
    allow_unauthenticated_access
    layout "public_status"

    def index
      @groups = public_groups
      build_status_page!
    end

    def show
      @group = Group.publicly_visible.find_by!(status_slug: params[:slug])
      @groups = [ @group ]
      build_status_page!
      render :index
    end

    private

    def public_groups
      Group.publicly_visible.includes(:hosts).order(:name)
    end

    def build_status_page!
      @generated_at = Time.current
      host_ids = @groups.flat_map { |g| g.hosts.map(&:id) }
      latest_probe_results = fetch_latest_probe_results(host_ids)
      
      @group_rows = @groups.map do |group|
        {
          group: group,
          host_rows: group.hosts.order(:name).map { |host| build_host_row(host, latest_probe_results[host.id]) }
        }
      end
      @host_rows = @group_rows.flat_map { |entry| entry[:host_rows] }
      @global_blocks = StatusPage::UptimeBucketBuilder.combine(@host_rows.map { |row| row[:blocks] })
      @overall_state = StatusPage::UptimeBucketBuilder.overall_state(@host_rows.map { |row| row[:state] })
      @incidents = StatusPage::IncidentBuilder.call(@groups.flat_map(&:hosts)).first(15)
    end

    def fetch_latest_probe_results(host_ids)
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

    def build_host_row(host, latest_result)
      blocks = StatusPage::UptimeBucketBuilder.for_host(host)

      {
        host: host,
        latest_result: latest_result,
        blocks: blocks,
        average_latency: average_latency_for(blocks),
        state: StatusPage::ResultStateCalculator.latest_state(host)
      }
    end

    def average_latency_for(blocks)
      latencies = blocks.filter_map { |bucket| bucket[:average_latency] }
      return nil if latencies.empty?

      (latencies.sum / latencies.size).round(2)
    end
  end
end
