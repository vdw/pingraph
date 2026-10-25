# The second sign-in step for users with two-factor authentication: a code from their
# authenticator app or a recovery code, after SessionsController checked the password.
class TwoFactorChallengesController < ApplicationController
  EXPIRES_IN = 5.minutes

  allow_unauthenticated_access
  before_action :set_pending_user
  # Per user, so an attacker who has the password can't spread guesses over many addresses.
  rate_limit to: 10, within: 3.minutes, only: :create, by: -> { @user.id },
    with: -> { redirect_to new_two_factor_challenge_path, alert: "Too many attempts. Wait a few minutes and try again." }

  def new
  end

  def create
    if @user.verify_second_factor(params[:code])
      session.delete(:two_factor)
      start_new_session_for @user
      redirect_to after_authentication_url
    else
      redirect_to new_two_factor_challenge_path, alert: "That code didn't work. Try again."
    end
  end

  private
    def set_pending_user
      pending = session[:two_factor]
      @user = User.find_by(id: pending["user_id"]) if pending.is_a?(Hash) && pending["expires_at"].to_i > Time.current.to_i
      return if @user&.two_factor_enabled?

      session.delete(:two_factor)
      redirect_to new_session_path, alert: "Sign in again."
    end
end
