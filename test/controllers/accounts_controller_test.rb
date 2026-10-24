require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "edit" do
    get edit_account_path
    assert_response :success
  end

  test "changes the password with the current one and signs out other sessions" do
    other_session = @user.sessions.create!

    patch account_path, params: { user: {
      email_address: @user.email_address, password: "new-password",
      password_confirmation: "new-password", password_challenge: "password"
    } }

    assert_redirected_to edit_account_path
    assert @user.reload.authenticate("new-password")
    assert_not Session.exists?(other_session.id)
    assert Session.exists?(Current.session.id)
  end

  test "rejects a wrong current password" do
    assert_no_changes -> { @user.reload.password_digest } do
      patch account_path, params: { user: {
        email_address: @user.email_address, password: "new-password",
        password_confirmation: "new-password", password_challenge: "wrong"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Current password is invalid"
  end

  test "requires the current password even when it is left out" do
    patch account_path, params: { user: { email_address: "changed@example.com" } }

    assert_response :unprocessable_entity
    assert_equal "one@example.com", @user.reload.email_address
  end

  test "changes the email and keeps the password when the password fields are blank" do
    patch account_path, params: { user: {
      email_address: "Changed@Example.com", password: "", password_confirmation: "", password_challenge: "password"
    } }

    assert_redirected_to edit_account_path
    @user.reload
    assert_equal "changed@example.com", @user.email_address
    assert @user.authenticate("password")
  end

  test "rejects a short or mismatched new password" do
    patch account_path, params: { user: {
      email_address: @user.email_address, password: "short", password_confirmation: "other", password_challenge: "password"
    } }

    assert_response :unprocessable_entity
    assert_includes response.body, "too short"
    assert_includes response.body, "doesn&#39;t match"
  end

  test "a pending password change blocks every other page" do
    @user.update!(must_change_password: true)

    get root_path
    assert_redirected_to edit_account_path

    get edit_settings_path
    assert_redirected_to edit_account_path

    get edit_account_path
    assert_response :success

    delete session_path
    assert_redirected_to new_session_path
  end

  test "a pending password change can't be cleared without a new password" do
    @user.update!(must_change_password: true)

    patch account_path, params: { user: {
      email_address: "changed@example.com", password: "", password_confirmation: "", password_challenge: "password"
    } }

    assert_response :unprocessable_entity
    assert @user.reload.must_change_password?
    assert_equal "one@example.com", @user.email_address
  end

  test "changing the password clears a pending password change" do
    @user.update!(must_change_password: true)

    patch account_path, params: { user: {
      email_address: @user.email_address, password: "new-password",
      password_confirmation: "new-password", password_challenge: "password"
    } }

    assert_redirected_to edit_account_path
    assert_not @user.reload.must_change_password?

    get root_path
    assert_response :success
  end

  test "requires authentication" do
    sign_out

    get edit_account_path
    assert_redirected_to new_session_path
  end
end
