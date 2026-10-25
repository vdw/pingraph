require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @me = users(:one)
    @other = users(:two)
    sign_in_as(@me)
  end

  test "lists users" do
    get users_path

    assert_response :success
    assert_includes response.body, @other.email_address
  end

  test "adds a user with a temporary password shown once" do
    get new_user_path
    assert_response :success

    assert_difference("User.count") do
      post users_path, params: { user: { email_address: "New@Example.com" } }
    end

    user = User.find_by!(email_address: "new@example.com")
    assert user.must_change_password?
    follow_redirect!
    password = css_select("#temporary-password").first.text
    assert user.authenticate(password)

    get users_path
    assert_not_includes response.body, password
  end

  test "rejects an invalid or taken email" do
    assert_no_difference("User.count") do
      post users_path, params: { user: { email_address: @other.email_address } }
    end
    assert_response :unprocessable_entity
  end

  test "removes another user and signs them out" do
    session = @other.sessions.create!

    assert_difference("User.count", -1) { delete user_path(@other) }

    assert_not Session.exists?(session.id)
  end

  test "can't remove, reset or change yourself here" do
    assert_no_difference("User.count") { delete user_path(@me) }
    assert_no_changes -> { @me.reload.password_digest } do
      post reset_password_user_path(@me)
    end
    assert_redirected_to users_path
  end

  test "resets another user's password" do
    post reset_password_user_path(@other)

    assert @other.reload.must_change_password?
    assert_not @other.authenticate("password")
    follow_redirect!
    assert @other.authenticate(css_select("#temporary-password").first.text)
  end

  test "turns off another user's two-factor authentication" do
    enable_two_factor(@other)

    delete two_factor_user_path(@other)

    assert_not @other.reload.two_factor_enabled?
  end
end
