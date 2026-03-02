class HostsController < ApplicationController
  before_action :set_host, only: %i[ show edit update destroy pings_data ]

  # GET /hosts or /hosts.json
  def index
    @hosts = Host.includes(:group).order("groups.name, hosts.name").joins(:group)
  end

  # GET /hosts/1 or /hosts/1.json
  def show
    @recent_pings = @host.pings.order(recorded_at: :desc).limit(20)
  end

  # GET /hosts/1/pings_data.json
  def pings_data
    pings = @host.pings.order(recorded_at: :asc).last(200)
    render json: pings.map { |p|
      {
        recorded_at: p.recorded_at.iso8601,
        latency:     p.latency,
        min_latency: p.min_latency,
        max_latency: p.max_latency,
        packet_loss: p.packet_loss
      }
    }
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

    # Only allow a list of trusted parameters through.
    def host_params
      params.expect(host: [ :name, :address, :interval, :group_id ])
    end
end
