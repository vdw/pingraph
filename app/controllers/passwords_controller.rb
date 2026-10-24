class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_email_delivery, only: %i[ new create ]
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "Password has been reset."
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private
    # Reset links go out through the SMTP server configured in Settings.
    def require_email_delivery
      return if Setting.current.email_enabled?

      redirect_to new_session_path, alert: "Password reset by email needs Email (SMTP) set up in Settings. " \
        "Ask whoever runs this Pingraph to run bin/rails pingraph:reset_password."
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
