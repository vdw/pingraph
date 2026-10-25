class AddTwoFactorToUsers < ActiveRecord::Migration[8.1]
  def change
    # TOTP secret (encrypted), set once setup is confirmed with a code.
    add_column :users, :otp_secret, :text
    add_column :users, :otp_enabled_at, :datetime
    # Time step of the last accepted code, so a code can't be used twice.
    add_column :users, :otp_last_used_at, :integer
    # JSON array of SHA-256 digests of the unused recovery codes.
    add_column :users, :otp_recovery_code_digests, :text
  end
end
