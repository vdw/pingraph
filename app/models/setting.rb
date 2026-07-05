require "uri"

class Setting < ApplicationRecord
  RETENTION_OPTIONS = [ 30, 60, 90 ].freeze
  DEFAULT_RETENTION_DAYS = 90
  SMTP_AUTHENTICATION_OPTIONS = %w[plain login cram_md5].freeze

  alias_attribute :ping_retention_days, :probe_result_retention_days

  # Secrets are encrypted at rest. Keys are provisioned by
  # config/initializers/active_record_encryption.rb.
  encrypts :slack_webhook_url
  encrypts :smtp_password

  before_validation :normalize_blanks

  validates :probe_result_retention_days, inclusion: { in: RETENTION_OPTIONS }

  # Slack channel
  validates :slack_webhook_url, presence: true, if: :slack_enabled?
  validate :slack_webhook_url_must_be_https, if: -> { slack_enabled? && slack_webhook_url.present? }

  # Email channel
  validates :smtp_address, :notification_from_email, :notification_recipient_email,
            presence: true, if: :email_enabled?
  validates :smtp_port, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535 }
  validates :smtp_authentication, inclusion: { in: SMTP_AUTHENTICATION_OPTIONS }
  validate :notification_emails_must_be_valid, if: :email_enabled?

  # A reachable base URL is required for the deep links embedded in alerts.
  validates :base_url, presence: true, if: :any_channel_enabled?
  validate :base_url_must_be_valid, if: -> { base_url.present? }

  # Belt-and-braces: refuse to enable a channel (which means persisting a secret) if the
  # encryption keys aren't resolvable, so a broken deploy fails as a friendly form error
  # rather than a 500 on save. Keys are normally always present (see the initializer).
  validate :encryption_must_be_configured, if: :any_channel_enabled?

  def self.current
    first_or_create!(probe_result_retention_days: DEFAULT_RETENTION_DAYS)
  end

  def any_channel_enabled?
    slack_enabled? || email_enabled?
  end

  # Options merged into Action Mailer's SMTP delivery for a single send. Built at send
  # time (not boot time) because SMTP is configured from the UI.
  def smtp_delivery_options
    {
      address: smtp_address,
      port: smtp_port,
      user_name: smtp_user_name.presence,
      password: smtp_password.presence,
      authentication: smtp_authentication.presence&.to_sym,
      enable_starttls_auto: smtp_starttls
    }.compact
  end

  # Absolute URL for a relative path using the configured base_url. Returns nil when no
  # base_url is set so callers can omit a link rather than render a broken one.
  def absolute_url(path)
    return nil if base_url.blank?

    "#{base_url.chomp('/')}/#{path.to_s.delete_prefix('/')}"
  end

  private

  def normalize_blanks
    self.slack_webhook_url = slack_webhook_url.presence
    self.smtp_password = smtp_password.presence
    self.smtp_address = smtp_address.presence
    self.smtp_user_name = smtp_user_name.presence
    self.notification_from_email = notification_from_email.presence
    self.notification_recipient_email = notification_recipient_email.presence
    self.base_url = base_url.presence
  end

  def slack_webhook_url_must_be_https
    uri = URI.parse(slack_webhook_url)
    errors.add(:slack_webhook_url, "must be a valid https:// URL") unless uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    errors.add(:slack_webhook_url, "must be a valid https:// URL")
  end

  def notification_emails_must_be_valid
    %i[notification_from_email notification_recipient_email].each do |field|
      value = public_send(field)
      next if value.blank?

      errors.add(field, "must be a valid email address") unless value.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end

  def base_url_must_be_valid
    uri = URI.parse(base_url)
    errors.add(:base_url, "must be a valid http(s):// URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:base_url, "must be a valid http(s):// URL")
  end

  def encryption_must_be_configured
    config = ActiveRecord::Encryption.config
    return if config.has_primary_key? && config.has_key_derivation_salt?

    errors.add(:base, "Encryption keys are not configured; cannot store notification secrets safely.")
  end
end
