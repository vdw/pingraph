# Turns two-factor authentication on and off for the signed-in user. Both need the current
# password, so a stolen session can't lock the owner out or remove the second factor.
class Accounts::TwoFactorsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[ create destroy ], with: -> { redirect_to edit_account_path, alert: "Try again later." }
  before_action :set_user

  # The secret lives in the (encrypted) session cookie until a code confirms it, so reloading
  # this page keeps showing the QR code already scanned.
  def new
    return redirect_to(edit_account_path, notice: "Two-factor authentication is already on.") if @user.two_factor_enabled?

    @secret = session[:pending_otp_secret] ||= User.generate_otp_secret
    @qr_code = RQRCode::QRCode.new(User.otp_provisioning_uri(@secret, @user.email_address))
  end

  def create
    secret = session[:pending_otp_secret]
    return redirect_to(new_account_two_factor_path) if secret.blank? || @user.two_factor_enabled?

    unless @user.authenticate(params[:password_challenge].to_s)
      return redirect_to(new_account_two_factor_path, alert: "Your current password is incorrect.")
    end

    if (codes = @user.enable_two_factor!(secret, params[:code]))
      session.delete(:pending_otp_secret)
      flash[:recovery_codes] = codes
      redirect_to edit_account_path, notice: "Two-factor authentication is on."
    else
      redirect_to new_account_two_factor_path, alert: "That code didn't work. Check your phone's clock and try the newest code."
    end
  end

  def destroy
    if @user.authenticate(params[:password_challenge].to_s)
      @user.disable_two_factor!
      redirect_to edit_account_path, notice: "Two-factor authentication is off."
    else
      redirect_to edit_account_path, alert: "Your current password is incorrect. Two-factor authentication is still on."
    end
  end

  private
    def set_user
      @user = Current.user
    end
end
