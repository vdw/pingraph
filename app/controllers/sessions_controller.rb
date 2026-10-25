class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  allow_pending_password_change only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      if user.two_factor_enabled?
        # The password was right; the session starts once the code is too.
        session[:two_factor] = { "user_id" => user.id, "expires_at" => TwoFactorChallengesController::EXPIRES_IN.from_now.to_i }
        redirect_to new_two_factor_challenge_path
      else
        start_new_session_for user
        redirect_to after_authentication_url
      end
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
