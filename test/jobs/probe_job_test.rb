require "test_helper"

class ProbeJobTest < ActiveJob::TestCase
  setup do
    @host = hosts(:one)
  end

  def with_stubbed_execute(&block)
    calls = []
    original = ProbeService.method(:execute)
    ProbeService.singleton_class.define_method(:execute) { |host| calls << host.id }
    block.call(calls)
  ensure
    ProbeService.singleton_class.define_method(:execute, original)
  end

  test "allows one queued or running probe per host and drops duplicates" do
    assert_equal :discard, ProbeJob.concurrency_on_conflict.to_sym
    assert_equal 1, ProbeJob.concurrency_limit
    assert_equal @host.id.to_s, ProbeJob.new(@host.id).concurrency_key.split("/").last
  end

  test "runs a probe that is on time" do
    with_stubbed_execute do |calls|
      job = ProbeJob.new(@host.id)
      job.scheduled_at = 5.seconds.ago
      job.perform_now

      assert_equal [ @host.id ], calls
    end
  end

  test "skips a probe that waited longer than the host's interval" do
    with_stubbed_execute do |calls|
      job = ProbeJob.new(@host.id)
      job.scheduled_at = 5.minutes.ago
      job.perform_now

      assert_empty calls
    end
  end

  test "retries when SQLite reports the database is locked" do
    original = ProbeService.method(:execute)
    ProbeService.singleton_class.define_method(:execute) { |_host| raise ActiveRecord::StatementTimeout, "database is locked" }

    assert_enqueued_with(job: ProbeJob, args: [ @host.id ]) do
      ProbeJob.perform_now(@host.id)
    end
  ensure
    ProbeService.singleton_class.define_method(:execute, original)
  end
end
