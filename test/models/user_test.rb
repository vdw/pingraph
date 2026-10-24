require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires a valid, unique email and a password of at least 8 characters" do
    user = User.new(email_address: "not-an-email", password: "short")

    assert_not user.valid?
    assert_includes user.errors[:email_address], "must be a valid email address"
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"

    user.email_address = users(:one).email_address
    assert_not user.valid?
    assert_includes user.errors[:email_address], "has already been taken"
  end

  test "reset_password! sets a temporary password, requires a change and signs out everywhere" do
    user = users(:one)
    user.sessions.create!

    password = user.reset_password!

    user.reload
    assert user.authenticate(password)
    assert user.must_change_password?
    assert_empty user.sessions
  end
end
