require "test_helper"

class SpeedTestServiceTest < ActiveSupport::TestCase
  test "execute parses receiver bits_per_second and converts to Mbps" do
    host = Host.create!(name: "Speed Target", address: "1.1.1.1", interval: 10, group: groups(:one))
    seen_command = nil

    original_capture3 = Open3.method(:capture3)

    Open3.singleton_class.define_method(:capture3, ->(*args) {
      if args == [ "iperf3", "--version" ]
        return [ "iperf3 3.0", "", Struct.new(:success?).new(true) ]
      end

      seen_command = args
      payload = {
        "end" => {
          "sum_received" => {
            "bits_per_second" => 125_000_000.0
          }
        }
      }

      [ payload.to_json, "", Struct.new(:success?).new(true) ]
    })

    result = SpeedTestService.execute(host)

    assert_equal [ "iperf3", "-c", "1.1.1.1", "-J", "-t", "5" ], seen_command
    assert result.success?
    assert_equal "tcp", result.protocol
    assert_equal 125.0, result.bandwidth_mbps
  ensure
    Open3.singleton_class.define_method(:capture3, original_capture3)
  end

  test "execute returns failure when iperf3 is missing" do
    host = Host.create!(name: "Speed Target", address: "1.1.1.1", interval: 10, group: groups(:one))

    original_capture3 = Open3.method(:capture3)

    Open3.singleton_class.define_method(:capture3, ->(*args) {
      assert_equal [ "iperf3", "--version" ], args
      raise Errno::ENOENT
    })

    result = SpeedTestService.execute(host)

    assert_not result.success?
  ensure
    Open3.singleton_class.define_method(:capture3, original_capture3)
  end

  test "execute refuses unsafe targets" do
    host = Host.create!(name: "Speed Target", address: "1.1.1.1", interval: 10, group: groups(:one))
    # Hosts can no longer be saved with such an address; simulate a legacy row.
    host.update_column(:address, "1.1.1.1; rm -rf /")

    original_capture3 = Open3.method(:capture3)

    Open3.singleton_class.define_method(:capture3, ->(*) {
      raise "capture3 should not be called for unsafe target"
    })

    result = SpeedTestService.execute(host)

    assert_not result.success?
    assert_includes result.error_message, "not a plain hostname or IP address"
  ensure
    Open3.singleton_class.define_method(:capture3, original_capture3)
  end

  test "execute reports the iperf3 error and how to fix it" do
    host = Host.create!(name: "Speed Target", address: "1.1.1.1", interval: 10, group: groups(:one))
    original_capture3 = Open3.method(:capture3)

    Open3.singleton_class.define_method(:capture3, ->(*args) {
      return [ "iperf3 3.0", "", Struct.new(:success?).new(true) ] if args == [ "iperf3", "--version" ]

      [ { "error" => "unable to connect to server: Connection refused" }.to_json, "", Struct.new(:success?).new(false) ]
    })

    result = SpeedTestService.execute(host)

    assert_not result.success?
    assert_includes result.error_message, "unable to connect to server"
    assert_includes result.error_message, "iperf3 -s"
  ensure
    Open3.singleton_class.define_method(:capture3, original_capture3)
  end
end
