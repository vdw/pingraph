class ApplicationMailer < ActionMailer::Base
  FALLBACK_FROM = "pingraph@localhost".freeze

  default from: -> { default_from_address }
  layout "mailer"

  private

  # The "From address" configured in Settings, else MAILER_FROM.
  def default_from_address
    Setting.current.notification_from_email.presence || ENV.fetch("MAILER_FROM", FALLBACK_FROM)
  rescue ActiveRecord::ActiveRecordError
    ENV.fetch("MAILER_FROM", FALLBACK_FROM)
  end

  # Links in emails use the Base URL from Settings when set, so they point at this
  # Pingraph instead of the placeholder host in the environment config.
  def default_url_options
    base_url = Setting.current.base_url
    return super if base_url.blank?

    uri = URI.parse(base_url)
    options = { host: uri.host, protocol: uri.scheme, port: (uri.port unless uri.port == uri.default_port) }
    options[:script_name] = uri.path.chomp("/") if uri.path.present? && uri.path != "/"
    super.merge(options.compact)
  rescue URI::InvalidURIError, ActiveRecord::ActiveRecordError
    super
  end
end
