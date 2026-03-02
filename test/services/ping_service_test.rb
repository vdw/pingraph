require "test_helper"

class PingServiceTest < ActiveSupport::TestCase
  test "execute uses strict ping timeouts" do
    host = hosts(:one)
    status = Struct.new(:exitstatus).new(1)
    original_capture3 = Open3.method(:capture3)

    Open3.singleton_class.define_method(:capture3, ->(*args) {
      assert_equal "ping", args[0]
      assert_includes args, "-W"
      assert_includes args, PingService::PACKET_TIMEOUT.to_s
      assert_includes args, "-w"
      assert_includes args, PingService::COMMAND_DEADLINE.to_s

      [
        "5 packets transmitted, 0 received, 100% packet loss, time 8008ms\n",
        "",
        status
      ]
    })

    assert_difference("host.pings.count", +1) do
      PingService.execute(host)
    end
  ensure
    Open3.singleton_class.define_method(:capture3, original_capture3)
  end
end
