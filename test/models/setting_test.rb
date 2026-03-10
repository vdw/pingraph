require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "validates ping retention options" do
    setting = Setting.new(ping_retention_days: 45)

    assert_not setting.valid?
    assert_includes setting.errors[:ping_retention_days], "is not included in the list"
  end
end
