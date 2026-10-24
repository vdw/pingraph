require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.take
    # Reset links are only offered when email can be sent.
    Setting.current.update_columns(email_enabled: true, smtp_address: "smtp.example.com")
  end

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "new and create redirect to sign in when email is not set up" do
    Setting.current.update_columns(email_enabled: false)

    get new_password_path
    assert_redirected_to new_session_path

    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "pingraph:reset_password"
  end

  test "reset email is sent through the SMTP server from Settings" do
    mail = PasswordsMailer.reset(@user)

    assert_equal "smtp.example.com", mail.delivery_method.settings[:address]
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "new-password", password_confirmation: "new-password" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no-match-1", password_confirmation: "no-match-2" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "doesn't match"
  end

  test "update rejects a too short password" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "short", password_confirmation: "short" }
    end

    follow_redirect!
    assert_notice "too short"
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
