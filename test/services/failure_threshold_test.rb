require "test_helper"

# The live status (ProbeService.status_for) and the public page's replay
# (StatusPage::ResultStateCalculator) must apply a host's failure_threshold the same way.
class FailureThresholdTest < ActiveSupport::TestCase
  setup do
    @host = Host.create!(group: groups(:one), name: "Router", address: "192.0.2.1", interval: 60,
      latency_threshold_ms: 100, notifications_enabled: false)
  end

  test "threshold 1 turns Down on the first failure" do
    @host.update!(failure_threshold: 1)

    persist(:fail)
    assert_equal "down", @host.reload.status
  end

  test "threshold 3 needs three failures for Down and three problems for Degraded" do
    @host.update!(failure_threshold: 3)

    persist(:ok)
    persist(:fail)
    persist(:fail)
    assert_equal "up", @host.reload.status, "two failures are not enough"
    persist(:fail)
    assert_equal "down", @host.reload.status

    persist(:ok)
    persist(:slow)
    persist(:slow)
    assert_equal "up", @host.reload.status
    persist(:slow)
    assert_equal "degraded", @host.reload.status
  end

  test "the status page replay matches the live status for every threshold" do
    sequence = %i[ok fail ok fail fail ok slow fail slow ok fail fail fail fail ok slow slow slow ok]

    [ 1, 2, 3, 5 ].each do |threshold|
      @host.probe_results.delete_all
      @host.update!(failure_threshold: threshold)
      @host.update_columns(status: Host.statuses[:unknown], consecutive_failures: 0, consecutive_issues: 0)
      start_at = Time.current

      live = sequence.each_with_index.map do |kind, index|
        persist(kind, at: start_at + index.minutes)
        @host.reload.status.to_sym
      end

      replayed = StatusPage::ResultStateCalculator
        .entries_for_host(@host, start_at: start_at - 1.minute, end_at: start_at + sequence.size.minutes)
        .map(&:state)

      # The replay starts from operational; the live status starts unknown.
      expected = live.map { |status| status == :up || status == :unknown ? :operational : status }
      assert_equal expected, replayed, "threshold #{threshold}"
    end
  end

  private

  def persist(kind, at: Time.current)
    result = ProbeService::Result.new(
      probe_type: :icmp,
      success: kind != :fail,
      latency: { ok: 10.0, slow: 500.0 }[kind],
      packet_loss: kind == :fail ? 100 : 0,
      metadata: {},
      recorded_at: at
    )
    ProbeService.send(:persist_result!, @host.reload, result)
  end
end
