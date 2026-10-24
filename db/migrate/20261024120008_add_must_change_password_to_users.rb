class AddMustChangePasswordToUsers < ActiveRecord::Migration[8.1]
  # The password db/seeds.rb used to set for every install.
  SEEDED_PASSWORD = "pingraph123".freeze

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    add_column :users, :must_change_password, :boolean, default: false, null: false

    # Existing installs still on the seeded password are asked to change it at next sign-in
    # (not in development, where db/seeds.rb keeps it on purpose).
    return if Rails.env.development?

    MigrationUser.reset_column_information
    MigrationUser.find_each do |user|
      next unless BCrypt::Password.new(user.password_digest).is_password?(SEEDED_PASSWORD)

      user.update_columns(must_change_password: true)
    rescue BCrypt::Errors::InvalidHash
      next
    end
  end

  def down
    remove_column :users, :must_change_password
  end
end
