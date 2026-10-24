class AccountsController < ApplicationController
  allow_pending_password_change only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { redirect_to edit_account_path, alert: "Try again later." }

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    attrs = account_params
    changing_password = attrs[:password].present?
    # Blank password fields mean "keep the current password".
    attrs = attrs.except(:password, :password_confirmation) unless changing_password

    if @user.must_change_password? && !changing_password
      @user.assign_attributes(attrs)
      @user.errors.add(:password, "must be changed before you continue")
      return render :edit, status: :unprocessable_entity
    end

    attrs[:must_change_password] = false if changing_password

    # password_challenge makes has_secure_password check the current password.
    if @user.update(attrs)
      # Sign out every other browser so a leaked password stops working everywhere.
      @user.sessions.where.not(id: Current.session.id).destroy_all if changing_password
      redirect_to edit_account_path, notice: "Your account was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def account_params
      params.expect(user: [ :email_address, :password, :password_confirmation, :password_challenge ]).tap do |attrs|
        # Always present so a missing field fails the check instead of skipping it.
        attrs[:password_challenge] = attrs[:password_challenge].to_s
      end
    end
end
