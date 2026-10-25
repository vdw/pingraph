# Replaces the signed-in user's recovery codes; the old ones stop working.
class Accounts::RecoveryCodesController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to edit_account_path, alert: "Try again later." }

  def create
    user = Current.user
    return redirect_to(edit_account_path) unless user.two_factor_enabled?

    if user.authenticate(params[:password_challenge].to_s)
      flash[:recovery_codes] = user.regenerate_recovery_codes!
      redirect_to edit_account_path, notice: "New recovery codes created. The old ones no longer work."
    else
      redirect_to edit_account_path, alert: "Your current password is incorrect."
    end
  end
end
