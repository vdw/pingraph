require "test_helper"

class StorageSecretTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir("storage_secret"))
    @path = @dir.join("nested", "secret")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "creates the file once with owner-only permissions and then reuses it" do
    assert_equal "first", StorageSecret.fetch(@path) { "first" }
    assert_equal "first", StorageSecret.fetch(@path) { "second" }
    assert_equal 0o600, @path.stat.mode & 0o777
    assert_equal [ "secret" ], @path.dirname.children.map { |child| child.basename.to_s }
  end

  test "replace! overwrites the file with owner-only permissions and leaves no temp file" do
    StorageSecret.fetch(@path) { "old" }
    StorageSecret.replace!(@path, "new")

    assert_equal "new", @path.read
    assert_equal 0o600, @path.stat.mode & 0o777
    assert_equal [ "secret" ], @path.dirname.children.map { |child| child.basename.to_s }
  end

  test "build_time? follows SECRET_KEY_BASE_DUMMY" do
    original = ENV["SECRET_KEY_BASE_DUMMY"]

    ENV["SECRET_KEY_BASE_DUMMY"] = "1"
    assert StorageSecret.build_time?

    ENV.delete("SECRET_KEY_BASE_DUMMY")
    assert_not StorageSecret.build_time?
  ensure
    ENV["SECRET_KEY_BASE_DUMMY"] = original
  end
end
