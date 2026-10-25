# Everyone who can sign in. All users are admins; nobody can remove themselves or the last user.
class UsersController < ApplicationController
  before_action :set_user, only: %i[ destroy reset_password disable_two_factor ]
  before_action :prevent_changing_yourself, only: %i[ destroy reset_password disable_two_factor ]

  def index
    @users = User.order(:email_address)
  end

  def new
    @user = User.new
  end

  # The new user gets a random password, shown once, which they must change at first sign-in.
  def create
    password = SecureRandom.base58(16)
    @user = User.new(email_address: params.expect(user: [ :email_address ])[:email_address],
      password: password, must_change_password: true)

    if @user.save
      flash[:temporary_password] = { "email_address" => @user.email_address, "password" => password }
      redirect_to users_path, notice: "Added #{@user.email_address}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    if User.count <= 1
      redirect_to users_path, alert: "Pingraph needs at least one user."
    else
      @user.destroy!
      redirect_to users_path, notice: "Removed #{@user.email_address}.", status: :see_other
    end
  end

  # Signs the user out everywhere; the temporary password must be changed at the next sign-in.
  def reset_password
    password = @user.reset_password!
    flash[:temporary_password] = { "email_address" => @user.email_address, "password" => password }
    redirect_to users_path, notice: "Reset the password for #{@user.email_address}.", status: :see_other
  end

  # For someone who lost their phone and their recovery codes.
  def disable_two_factor
    @user.disable_two_factor!
    redirect_to users_path, notice: "Turned off two-factor authentication for #{@user.email_address}.", status: :see_other
  end

  private
    def set_user
      @user = User.find(params.expect(:id))
    end

    def prevent_changing_yourself
      return unless @user == Current.user

      redirect_to users_path, alert: "Change your own account on the Account page.", status: :see_other
    end
end
