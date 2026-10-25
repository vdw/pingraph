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

  test "two-factor setup needs a correct code and returns recovery codes" do
    user = users(:one)
    secret = User.generate_otp_secret

    assert_nil user.enable_two_factor!(secret, "000000")
    assert_not user.reload.two_factor_enabled?

    codes = user.enable_two_factor!(secret, current_code(secret))
    assert user.reload.two_factor_enabled?
    assert_equal User::RECOVERY_CODE_COUNT, codes.size
    assert codes.all? { |code| code.match?(/\A[a-z2-9]{5}-[a-z2-9]{5}\z/) }
    assert_equal secret, user.otp_secret
    assert_not_includes User.connection.select_value("SELECT otp_secret FROM users WHERE id = #{user.id}"), secret
  end

  test "an authenticator code works once" do
    user = users(:one)
    secret, = enable_two_factor(user)
    code = current_code(secret)

    assert user.verify_second_factor(code)
    assert_not user.reload.verify_second_factor(code)

    travel 30.seconds do
      assert user.reload.verify_second_factor(" #{current_code(secret)[0, 3]} #{current_code(secret)[3, 3]} ")
    end
  end

  test "a recovery code works once, in any case and with or without the dash" do
    user = users(:one)
    _, codes = enable_two_factor(user)

    assert user.verify_second_factor(codes.first.upcase.delete("-"))
    assert_not user.verify_second_factor(codes.first)
    assert_equal User::RECOVERY_CODE_COUNT - 1, user.reload.recovery_codes_left
    assert_not user.verify_second_factor("wrong-codes")
  end

  test "new recovery codes replace the old ones" do
    user = users(:one)
    _, old_codes = enable_two_factor(user)

    new_codes = user.regenerate_recovery_codes!

    assert_not user.verify_second_factor(old_codes.first)
    assert user.verify_second_factor(new_codes.first)
  end

  test "turning two-factor off clears the secret and codes" do
    user = users(:one)
    secret, codes = enable_two_factor(user)

    user.disable_two_factor!

    assert_not user.reload.two_factor_enabled?
    assert_nil user.otp_secret
    assert_not user.verify_second_factor(current_code(secret))
    assert_not user.verify_second_factor(codes.first)
  end
end
