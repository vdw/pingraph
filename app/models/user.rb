class User < ApplicationRecord
  MINIMUM_PASSWORD_LENGTH = 8

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true

  # Lockout recovery (bin/rails pingraph:reset_password). Signs the user out everywhere and
  # returns the new password, which they must change at their next sign-in.
  def reset_password!
    SecureRandom.base58(16).tap do |password|
      transaction do
        update!(password: password, must_change_password: true)
        sessions.destroy_all
      end
    end
  end
end
