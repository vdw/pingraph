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
      @group_rows = @groups.map do |group|
        {
          group: group,
          host_rows: group.hosts.order(:name).map { |host| build_host_row(host) }
        }
      end
      @host_rows = @group_rows.flat_map { |entry| entry[:host_rows] }
      @global_blocks = StatusPage::UptimeBucketBuilder.combine(@host_rows.map { |row| row[:blocks] })
      @overall_state = StatusPage::UptimeBucketBuilder.overall_state(@host_rows.map { |row| row[:state] })
      @incidents = StatusPage::IncidentBuilder.call(@groups.flat_map(&:hosts)).first(15)
    end

    def build_host_row(host)
      blocks = StatusPage::UptimeBucketBuilder.for_host(host)
      latest_result = host.latest_probe_result

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
