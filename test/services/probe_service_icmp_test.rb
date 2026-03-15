require "test_helper"

class ProbeServiceIcmpTest < ActiveSupport::TestCase
  test "probe_icmp uses strict ping timeouts" do
    host = hosts(:one)
    host.update_columns(probe_type: Host.probe_types.fetch("icmp"), updated_at: Time.current)
    status = Struct.new(:exitstatus).new(1)
    original_capture3 = Open3.method(:capture3)

    Open3.singleton_class.define_method(:capture3, ->(*args) {
      assert_equal "ping", args[0]
      assert_includes args, "-W"
      assert_includes args, ProbeService::ICMP_PACKET_TIMEOUT.to_s
      assert_includes args, "-w"
      assert_includes args, ProbeService::ICMP_COMMAND_DEADLINE.to_s

      [
        "5 packets transmitted, 0 received, 100% packet loss, time 8008ms\n",
        "",
        status
      ]
    })

    assert_difference("host.probe_results.count", +1) do
      ProbeService.execute(host)
    end
  ensure
    Open3.singleton_class.define_method(:capture3, original_capture3)
  end
end
