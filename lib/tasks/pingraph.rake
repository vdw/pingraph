namespace :pingraph do
  desc "Set a new random password for a user (EMAIL optional when there is only one user)"
  task :reset_password, [ :email ] => :environment do |_task, args|
    user =
      if args[:email].present?
        User.find_by(email_address: args[:email].strip.downcase)
      elsif User.one?
        User.first
      end

    unless user
      users = User.order(:email_address).pluck(:email_address)
      abort "No such user. Run: bin/rails \"pingraph:reset_password[EMAIL]\" with one of: #{users.join(', ')}"
    end

    password = user.reset_password!
    puts "New password for #{user.email_address}: #{password}"
    puts "You'll be asked to change it at your next sign-in. All sessions were signed out."
  end

  desc "Turn off two-factor authentication for a user who lost their phone and recovery codes"
  task :disable_two_factor, [ :email ] => :environment do |_task, args|
    with_two_factor = User.where.not(otp_enabled_at: nil)
    user =
      if args[:email].present?
        User.find_by(email_address: args[:email].strip.downcase)
      elsif with_two_factor.one?
        with_two_factor.first
      end

    unless user
      users = with_two_factor.order(:email_address).pluck(:email_address)
      abort "No such user. Run: bin/rails \"pingraph:disable_two_factor[EMAIL]\" with one of: #{users.join(', ').presence || '(nobody has it on)'}"
    end

    user.disable_two_factor!
    puts "Two-factor authentication is off for #{user.email_address}. They can sign in with their password and turn it on again."
  end

  desc "Replace storage/encryption.key with a new key and re-encrypt all secrets (restart Pingraph afterwards)"
  task rotate_encryption_key: :environment do
    count = EncryptionKeyRotation.new.call
    puts "Generated a new storage/encryption.key and re-encrypted #{count} #{'record'.pluralize(count)}."
    puts "Restart Pingraph now so every process uses the new key."
  rescue EncryptionKeyRotation::Error => e
    abort e.message
  end

  # Run after db:prepare (which the Docker image runs on every boot, before the server starts).
  task rotate_leaked_encryption_key: :environment do
    rotation = EncryptionKeyRotation.new
    next unless rotation.needed?

    count = rotation.call
    puts "[Pingraph] storage/encryption.key was a key published inside older Docker images, so it " \
         "was replaced with a new one and #{count} #{'record'.pluralize(count)} re-encrypted. If this " \
         "database was ever copied elsewhere, also replace your Slack webhook and SMTP password."
  end
end

Rake::Task["db:prepare"].enhance { Rake::Task["pingraph:rotate_leaked_encryption_key"].invoke }
