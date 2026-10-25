class User < ApplicationRecord
  MINIMUM_PASSWORD_LENGTH = 8
  OTP_ISSUER = "Pingraph"
  RECOVERY_CODE_COUNT = 10

  has_secure_password
  has_many :sessions, dependent: :destroy

  # The TOTP secret, set when two-factor authentication is turned on.
  encrypts :otp_secret

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true

  def two_factor_enabled?
    otp_enabled_at.present?
  end

  def self.generate_otp_secret
    ROTP::Base32.random
  end

  # For the QR code an authenticator app scans.
  def self.otp_provisioning_uri(secret, email_address)
    ROTP::TOTP.new(secret, issuer: OTP_ISSUER).provisioning_uri(email_address)
  end

  # Turns on two-factor authentication once code proves the app has the secret. Returns
  # the recovery codes (shown once), or nil when the code is wrong.
  def enable_two_factor!(secret, code)
    timestep = verify_totp(secret, code)
    return nil unless timestep

    codes = generate_recovery_codes
    update!(otp_secret: secret, otp_enabled_at: Time.current, otp_last_used_at: timestep,
      otp_recovery_code_digests: codes.map { |recovery_code| recovery_code_digest(recovery_code) }.to_json)
    codes
  end

  def disable_two_factor!
    update!(otp_secret: nil, otp_enabled_at: nil, otp_last_used_at: nil, otp_recovery_code_digests: nil)
  end

  # Accepts a code from the authenticator app (each one only once) or an unused recovery code.
  def verify_second_factor(code)
    return false unless two_factor_enabled?

    code = code.to_s.gsub(/[\s-]/, "").downcase
    if code.match?(/\A\d{6}\z/)
      timestep = verify_totp(otp_secret, code, after: otp_last_used_at)
      # Conditional update, so two requests racing with the same code can't both pass.
      timestep.present? && User.where(id: id).where("otp_last_used_at IS NULL OR otp_last_used_at < ?", timestep)
                                .update_all(otp_last_used_at: timestep) == 1
    else
      consume_recovery_code(code)
    end
  end

  def recovery_codes_left
    recovery_code_digests.size
  end

  # Replaces every recovery code; returns the new ones (shown once).
  def regenerate_recovery_codes!
    generate_recovery_codes.tap do |codes|
      update!(otp_recovery_code_digests: codes.map { |recovery_code| recovery_code_digest(recovery_code) }.to_json)
    end
  end

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

  private
    # Returns the time step of the matching code, or nil. Accepts the previous 30-second code
    # too, for clock drift and slow typing.
    def verify_totp(secret, code, after: nil)
      ROTP::TOTP.new(secret, issuer: OTP_ISSUER).verify(code.to_s.gsub(/\s/, ""), drift_behind: 30, after: after)
    end

    # 10 characters from 31 letters and digits without look-alikes (about 50 bits), as "xxxxx-xxxxx".
    def generate_recovery_codes
      Array.new(RECOVERY_CODE_COUNT) do
        Array.new(10) { "abcdefghjkmnpqrstuvwxyz23456789"[SecureRandom.random_number(31)] }.join.insert(5, "-")
      end
    end

    def recovery_code_digests
      JSON.parse(otp_recovery_code_digests.presence || "[]")
    end

    def recovery_code_digest(code)
      Digest::SHA256.hexdigest(code.delete("-").downcase)
    end

    def consume_recovery_code(code)
      digest = recovery_code_digest(code)
      with_lock do
        digests = recovery_code_digests
        next false unless digests.include?(digest)

        update!(otp_recovery_code_digests: (digests - [ digest ]).to_json)
        true
      end
    end
end
