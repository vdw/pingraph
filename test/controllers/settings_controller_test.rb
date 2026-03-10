require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    Setting.delete_all
  end

  test "should get edit" do
    get edit_settings_url

    assert_response :success
    assert_equal 90, Setting.current.ping_retention_days
  end

  test "should update setting" do
    patch settings_url, params: { setting: { ping_retention_days: 60 } }

    assert_redirected_to edit_settings_url
    assert_equal 60, Setting.current.ping_retention_days
  end

  test "should reject invalid retention days" do
    patch settings_url, params: { setting: { ping_retention_days: 45 } }

    assert_response :unprocessable_entity
    assert_equal 90, Setting.current.ping_retention_days
  end
end
