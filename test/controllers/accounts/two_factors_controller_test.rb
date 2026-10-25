require "test_helper"

class Accounts::TwoFactorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  # The secret shown on the setup page, read back from the manual-entry key.
  def setup_secret
    get new_account_two_factor_path
    assert_response :success
    assert_select "img[alt=?]", "QR code for your authenticator app"
    css_select("#otp-secret").first.text.delete(" ")
  end

  test "shows the same secret until setup is finished" do
    assert_equal setup_secret, setup_secret
  end

  test "turns two-factor on with a correct code and the current password, then shows recovery codes" do
    secret = setup_secret

    post account_two_factor_path, params: { code: current_code(secret), password_challenge: "password" }

    assert_redirected_to edit_account_path
    assert @user.reload.two_factor_enabled?
    follow_redirect!
    assert_includes response.body, "Save your recovery codes now"
    assert_select "li", minimum: User::RECOVERY_CODE_COUNT
  end

  test "needs the current password and a correct code" do
    secret = setup_secret

    post account_two_factor_path, params: { code: current_code(secret), password_challenge: "wrong" }
    assert_not @user.reload.two_factor_enabled?

    post account_two_factor_path, params: { code: "000000", password_challenge: "password" }
    assert_not @user.reload.two_factor_enabled?
    assert_redirected_to new_account_two_factor_path
  end

  test "turning it off needs the current password" do
    enable_two_factor(@user)

    delete account_two_factor_path, params: { password_challenge: "wrong" }
    assert @user.reload.two_factor_enabled?

    delete account_two_factor_path, params: { password_challenge: "password" }
    assert_not @user.reload.two_factor_enabled?
  end

  test "new recovery codes need the current password" do
    _, old_codes = enable_two_factor(@user)

    post account_recovery_codes_path, params: { password_challenge: "wrong" }
    assert @user.reload.verify_second_factor(old_codes.first)

    post account_recovery_codes_path, params: { password_challenge: "password" }
    assert_not @user.reload.verify_second_factor(old_codes.second)
    follow_redirect!
    assert_includes response.body, "Save your recovery codes now"
  end
end
