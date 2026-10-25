require "test_helper"

class TwoFactorChallengesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @secret, @recovery_codes = enable_two_factor(@user)
  end

  def sign_in_with_password
    post session_path, params: { email_address: @user.email_address, password: "password" }
  end

  test "the password alone doesn't sign in a user with two-factor on" do
    sign_in_with_password

    assert_redirected_to new_two_factor_challenge_path
    assert_nil cookies[:session_id]
    get root_path
    assert_redirected_to new_session_path
  end

  test "the password and a current code sign in" do
    sign_in_with_password
    get new_two_factor_challenge_path
    assert_response :success

    post two_factor_challenge_path, params: { code: current_code(@secret) }

    assert_redirected_to root_path
    assert cookies[:session_id].present?
  end

  test "a recovery code signs in too" do
    sign_in_with_password
    post two_factor_challenge_path, params: { code: @recovery_codes.first }

    assert_redirected_to root_path
    assert_equal User::RECOVERY_CODE_COUNT - 1, @user.reload.recovery_codes_left
  end

  test "a wrong code doesn't sign in" do
    sign_in_with_password
    post two_factor_challenge_path, params: { code: "000000" }

    assert_redirected_to new_two_factor_challenge_path
    assert_nil cookies[:session_id]
  end

  test "the code step needs a recent correct password" do
    get new_two_factor_challenge_path
    assert_redirected_to new_session_path

    sign_in_with_password
    travel TwoFactorChallengesController::EXPIRES_IN + 1.second do
      post two_factor_challenge_path, params: { code: current_code(@secret) }
      assert_redirected_to new_session_path
      assert_nil cookies[:session_id]
    end
  end

  test "users without two-factor still sign in with the password" do
    @user.disable_two_factor!
    sign_in_with_password

    assert_redirected_to root_path
  end
end
