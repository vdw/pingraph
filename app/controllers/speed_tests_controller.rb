class SpeedTestsController < ApplicationController
  before_action :load_hosts
  before_action :set_selected_host

  # GET /speed_tests
  def index
    load_speed_tests
  end

  # GET /speed_tests/panel.turbo_stream
  def panel
    load_speed_tests

    render turbo_stream: turbo_stream.replace(
      "speed_tests_content",
      partial: "speed_tests/content",
      locals: panel_locals
    )
  end

  # POST /speed_tests/run
  def run
    if @selected_host.nil?
      redirect_to speed_tests_path, alert: "Please select a host to run the speed test."
      return
    end

    unless @selected_host.speed_test_in_progress?
      speed_test = @selected_host.speed_tests.create!(protocol: "tcp", status: :queued)
      PerformSpeedTestJob.perform_later(speed_test.id)
    end

    load_speed_tests

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "speed_tests_content",
          partial: "speed_tests/content",
          locals: panel_locals
        )
      end
      format.html { redirect_to speed_tests_path(host_id: @selected_host.id), notice: "Speed test started." }
    end
  end

  private

  def load_hosts
    @hosts = Host.includes(:group).joins(:group).order("groups.name, hosts.name")
  end

  def set_selected_host
    host_id = params[:host_id].presence
    @selected_host = if host_id
      @hosts.find { |host| host.id == host_id.to_i }
    else
      @hosts.first
    end
  end

  def load_speed_tests
    @recent_speed_tests = SpeedTest.includes(host: :group)
      .order(Arel.sql("COALESCE(recorded_at, created_at) DESC"), created_at: :desc)
      .limit(100)
  end

  def panel_locals
    {
      hosts: @hosts,
      selected_host: @selected_host,
      recent_speed_tests: @recent_speed_tests
    }
  end
end
