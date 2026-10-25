# Turns on two-factor authentication for a user in tests; returns [secret, recovery codes].
module TwoFactorTestHelper
  def enable_two_factor(user)
    secret = User.generate_otp_secret
    # The previous 30-second code, so the current one is still unused.
    codes = user.enable_two_factor!(secret, ROTP::TOTP.new(secret).at(30.seconds.ago))
    [ secret, codes ]
  end

  def current_code(secret)
    ROTP::TOTP.new(secret).now
  end
end

ActiveSupport.on_load(:active_support_test_case) { include TwoFactorTestHelper }
ActiveSupport.on_load(:action_dispatch_integration_test) { include TwoFactorTestHelper }
