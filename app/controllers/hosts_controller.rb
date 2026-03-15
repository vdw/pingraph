class HostsController < ApplicationController
  CHART_WINDOWS = {
    "3h" => 3.hours,
    "12h" => 12.hours,
    "24h" => 24.hours,
    "7d" => 7.days
  }.freeze

  MANUAL_INTERVALS = {
    "raw" => nil,
    "5m" => 5,
    "30m" => 30,
    "120m" => 120
  }.freeze

  before_action :set_host, only: %i[ show edit update destroy probe_results_data probe_chart ]

  # GET /hosts or /hosts.json
  def index
    @hosts = Host.includes(:group).order("groups.name, hosts.name").joins(:group)
  end

  # GET /hosts/1 or /hosts/1.json
  def show
    @recent_probe_results = @host.probe_results.order(recorded_at: :desc).limit(20)
    @chart_window = normalize_window(params[:window])
    @chart_resolution = normalize_resolution(params[:resolution])
  end

  # GET /hosts/1/probe_chart
  def probe_chart
    @chart_window = normalize_window(params[:window])
    @chart_resolution = normalize_resolution(params[:resolution])
  end

  # GET /hosts/1/probe_results_data.json
  def probe_results_data
    chart_window = normalize_window(params[:window])
    chart_resolution = normalize_resolution(params[:resolution])
    start_time = Time.current - CHART_WINDOWS.fetch(chart_window)
    interval_minutes = interval_for(chart_window, chart_resolution)

    probe_results = if interval_minutes.nil?
      @host.probe_results.where("recorded_at >= ?", start_time).order(recorded_at: :asc)
    else
      @host.probe_results.downsampled_for_range(start_time, interval_minutes).order(Arel.sql("bucket_epoch ASC"))
    end

    render json: probe_results.map { |result| serialize_probe_result(result, interval_minutes) }
  end

  # GET /hosts/new
  def new
    @host = Host.new
  end

  # GET /hosts/1/edit
  def edit
  end

  # POST /hosts or /hosts.json
  def create
    @host = Host.new(host_params)

    respond_to do |format|
      if @host.save
        format.html { redirect_to @host, notice: "Host was successfully created." }
        format.json { render :show, status: :created, location: @host }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @host.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /hosts/1 or /hosts/1.json
  def update
    respond_to do |format|
      if @host.update(host_params)
        format.html { redirect_to @host, notice: "Host was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @host }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @host.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /hosts/1 or /hosts/1.json
  def destroy
    @host.destroy!

    respond_to do |format|
      format.html { redirect_to hosts_path, notice: "Host was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_host
      @host = Host.find(params.expect(:id))
    end

    def normalize_window(window)
      return "24h" unless CHART_WINDOWS.key?(window)

      window
    end

    def normalize_resolution(resolution)
      return "auto" if resolution.blank?

      MANUAL_INTERVALS.key?(resolution) ? resolution : "auto"
    end

    def interval_for(chart_window, chart_resolution)
      return MANUAL_INTERVALS.fetch(chart_resolution) if MANUAL_INTERVALS.key?(chart_resolution)

      case chart_window
      when "3h"
        nil
      when "7d"
        30
      else
        5
      end
    end

    def serialize_probe_result(result, interval_minutes)
      recorded_at = if interval_minutes.nil?
        result.recorded_at
      else
        Time.at(result.bucket_epoch.to_i).utc
      end

      probe_type = if result.respond_to?(:has_attribute?) && result.has_attribute?(:probe_type)
        result.probe_type
      else
        "icmp"
      end

      success = if probe_type == "icmp" && result.packet_loss.present?
        result.packet_loss.to_i < 100
      elsif result.respond_to?(:has_attribute?) && result.has_attribute?(:success)
        result.success
      else
        true
      end

      status_code = if result.respond_to?(:has_attribute?) && result.has_attribute?(:status_code)
        result.status_code
      end

      error_message = if result.respond_to?(:has_attribute?) && result.has_attribute?(:error_message)
        result.error_message
      end

      {
        recorded_at: recorded_at.iso8601,
        probe_type: probe_type,
        success: success,
        latency: result.latency&.to_f,
        min_latency: result.min_latency&.to_f,
        max_latency: result.max_latency&.to_f,
        packet_loss: result.packet_loss,
        status_code: status_code,
        error_message: error_message
      }
    end

    # Only allow a list of trusted parameters through.
    def host_params
      params.expect(host: [ :name, :address, :interval, :group_id, :probe_type, :port, :expected_status_code, :expected_status_code_range, :verify_ssl ])
    end
end
