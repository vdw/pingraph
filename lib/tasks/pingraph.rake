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
end
