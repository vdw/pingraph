require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "validates probe result retention options" do
    setting = Setting.new(probe_result_retention_days: 45)

    assert_not setting.valid?
    assert_includes setting.errors[:probe_result_retention_days], "is not included in the list"
  end
end
