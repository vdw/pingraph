class Host < ApplicationRecord
  DEFAULT_LATENCY_THRESHOLD_MS = 350.0
  # A sample counts as a problem at 2 of 5 lost packets; a single dropped packet is noise.
  DEGRADED_PACKET_LOSS_PERCENT = 40
  # Default for failure_threshold: checks in a row before the host turns Down (failed) or
  # Degraded (failed, slow or lossy).
  DEFAULT_FAILURE_THRESHOLD = 2
  MAX_FAILURE_THRESHOLD = 10
  HTTP_METHODS = %w[GET HEAD POST PUT PATCH DELETE OPTIONS].freeze
  HTTP_METHODS_WITH_BODY = %w[POST PUT PATCH].freeze
  MAX_TIMEOUT_SECONDS = 60
  MAX_REDIRECTS_LIMIT = 20
  # One "Name: value" per line; the name is an HTTP token (RFC 9110).
  REQUEST_HEADER_LINE = /\A[!#$%&'*+.^_`|~0-9A-Za-z-]+:[^\r\n]*\z/
  DNS_RECORD_TYPES = %w[A AAAA CNAME MX NS TXT].freeze
  # Docker container names ([a-zA-Z0-9][a-zA-Z0-9_.-]+) and IDs; also safe inside a URL path.
  DOCKER_CONTAINER = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/
  DEFAULT_DOCKER_HOST = "unix:///var/run/docker.sock".freeze
  DEFAULT_REDIS_PORT = 6379
  PROBE_TYPE_LABELS = {
    "icmp" => "Ping (ICMP)", "http" => "HTTP(S)", "tcp" => "TCP port", "dns" => "DNS",
    "push" => "Push (heartbeat)", "docker" => "Docker container", "redis" => "Redis"
  }.freeze

  belongs_to :group
  # delete_all: one DELETE statement instead of instantiating ~130k rows per busy host.
  has_many :probe_results, dependent: :delete_all
  has_many :speed_tests, dependent: :delete_all
  has_many :notification_deliveries, dependent: :nullify

  # HTTP check credentials (see Setting for how keys are provisioned). basic_auth_user and
  # basic_auth_password are also the Redis AUTH username (optional) and password.
  encrypts :request_headers
  encrypts :request_body
  encrypts :basic_auth_password

  enum :probe_type, {
    icmp: 0,
    http: 1,
    tcp: 2,
    dns: 3,
    push: 4,
    docker: 5,
    redis: 6
  }, default: :icmp

  enum :status, {
    unknown: 0,
    up: 1,
    degraded: 2,
    down: 3
  }, default: :unknown

  # Mirrors the status enum. Tracks the last state the user was actually notified about,
  # which is the baseline for alert de-duplication. Prefixed to avoid method collisions
  # with the identically-valued :status enum (e.g. #last_notified_up? vs #up?).
  enum :last_notified_status, {
    unknown: 0,
    up: 1,
    degraded: 2,
    down: 3
  }, default: :unknown, prefix: :last_notified

  validates :name, presence: true
  validates :address, presence: true, unless: :push?
  validate :address_unique_within_group
  validates :interval, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 10 }
  validates :latency_threshold_ms, numericality: { greater_than: 0 }
  validates :failure_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_FAILURE_THRESHOLD }
  validates :port, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535 }, if: -> { tcp? || redis? }
  validates :expected_status_code, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 599 }, if: :http?
  validates :expected_status_code_range, inclusion: { in: %w[exact 2xx 3xx 4xx 5xx] }, if: :http?
  validates :verify_ssl, inclusion: { in: [ true, false ] }, if: :http?
  validates :timeout_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_TIMEOUT_SECONDS }
  validate :timeout_must_be_shorter_than_interval
  validates :http_method, inclusion: { in: HTTP_METHODS }, if: :http?
  validates :max_redirects, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_REDIRECTS_LIMIT }, if: :http?
  validates :ssl_expiry_warn_days, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 365 }, allow_nil: true, if: :http?
  validate :http_options_must_be_consistent, if: :http?
  validates :dns_record_type, inclusion: { in: DNS_RECORD_TYPES }, if: :dns?
  validate :dns_server_must_be_an_ip_address, if: :dns?
  validate :docker_host_must_be_valid, if: :docker?

  validate :address_must_be_valid_http_url, if: :http?
  validate :address_must_be_valid_network_target, if: -> { icmp? || tcp? || redis? }
  validate :address_must_be_valid_domain_name, if: :dns?
  validate :address_must_be_valid_container, if: :docker?
  validate :probe_type_immutable, on: :update

  before_validation :normalize_probe_specific_fields
  before_create :regenerate_push_token, if: :push?
  # A new interval takes effect on the next poller run instead of after the old one.
  before_save -> { self.next_probe_at = nil }, if: :interval_changed?

  def latest_probe_result
    probe_results.order(recorded_at: :desc).first
  end

  # The persisted status is computed by ProbeService from consecutive samples, so a single
  # bad sample does not flip the badge (and no extra query is needed per host).
  # :stale when checks have stopped, so a dead worker doesn't leave hosts showing Up.
  def status_badge
    stale? ? :stale : status.to_sym
  end

  # No check for three intervals (and at least ProbeHealth::STALL_AFTER, so a short restart
  # doesn't flag fast hosts): the stored status is out of date.
  def stale?(now = Time.current)
    last_probed_at.present? && last_probed_at < now - [ interval.seconds * 3, ProbeHealth::STALL_AFTER ].max
  end

  # True when this one sample is a problem: failed, too slow, or too much packet loss.
  # Status only changes after several of these in a row (see ProbeService).
  def result_degraded?(result)
    return false if result.nil?
    success = result.respond_to?(:success?) ? result.success? : result.success

    return true unless success
    return true if result_lossy?(result)

    result_slow?(result)
  end

  def result_lossy?(result)
    icmp_result = result.respond_to?(:icmp?) ? result.icmp? : result.probe_type.to_s == "icmp"
    icmp_result && result.packet_loss.to_i >= DEGRADED_PACKET_LOSS_PERCENT
  end

  def result_slow?(result)
    result.latency.present? && result.latency.to_f > latency_threshold_ms.to_f
  end

  def http_status_matches?(status_code)
    status_code = status_code.to_i
    case expected_status_code_range
    when "2xx"
      status_code.between?(200, 299)
    when "3xx"
      status_code.between?(300, 399)
    when "4xx"
      status_code.between?(400, 499)
    when "5xx"
      status_code.between?(500, 599)
    else
      status_code == expected_status_code
    end
  end

  # The keyword check passes when the keyword is found (or, inverted, when it isn't).
  def keyword_matches?(body)
    body.to_s.include?(keyword) != keyword_invert?
  end

  # request_headers as a hash; lines that don't parse are skipped (validation rejects them).
  def parsed_request_headers
    request_headers.to_s.lines.filter_map do |line|
      name, value = line.strip.split(":", 2)
      [ name.strip, value.to_s.strip ] if value && line.strip.match?(REQUEST_HEADER_LINE)
    end.to_h
  end

  def ssl_expiring_soon?(now = Time.current)
    ssl_expires_at.present? && ssl_expiry_warn_days.present? && ssl_expires_at <= now + ssl_expiry_warn_days.days
  end

  def normalized_http_address
    value = address.to_s.strip
    return value if value.start_with?("http://", "https://")

    "https://#{value}"
  end

  # What the check targets, for lists and headers.
  def display_address
    case probe_type.to_sym
    when :push then "Push"
    when :tcp, :redis then address.to_s.include?(":") ? "[#{address}]:#{port}" : "#{address}:#{port}"
    when :dns then [ address, dns_record_type, (" @ #{dns_server}" if dns_server.present?) ].compact.join(" ").squeeze(" ")
    when :docker then docker_host.present? ? "#{address} on #{docker_host}" : address
    else address
    end
  end

  def probe_type_label
    PROBE_TYPE_LABELS.fetch(probe_type)
  end

  # The secret in the push URL. Changing it breaks every script using the old URL.
  def regenerate_push_token
    self.push_token = SecureRandom.base58(24)
  end

  # "unix:///var/run/docker.sock" => [:unix, "/var/run/docker.sock"]; "tcp://proxy:2375" =>
  # [:tcp, "proxy", 2375]. nil when the value isn't one of those forms.
  def docker_endpoint
    uri = URI.parse(docker_host.presence || DEFAULT_DOCKER_HOST)
    case uri.scheme
    when "unix"
      [ :unix, uri.path ] if uri.host.blank? && uri.path.to_s.start_with?("/")
    when "tcp", "http"
      [ :tcp, uri.hostname, uri.port ] if NetworkAddress.valid?(uri.hostname) && uri.port && uri.path.blank?
    end
  rescue URI::InvalidURIError
    nil
  end

  def speed_test_in_progress?
    speed_tests.in_progress.where(updated_at: (SpeedTest::STALE_AFTER.ago)..).exists?
  end

  def recent_speed_tests(limit = 5)
    speed_tests.recent.limit(limit)
  end

  def publicly_visible?
    group.is_public?
  end

  def public_label
    "#{name} (#{probe_type.upcase})"
  end

  private

  def address_unique_within_group
    return if address.blank? || group_id.blank? || push?

    scope = Host.where(group_id: group_id, address: address, probe_type: probe_type)
    scope = scope.where(port: port) if tcp? || redis?
    scope = scope.where(dns_record_type: dns_record_type, dns_server: dns_server) if dns?
    scope = scope.where(docker_host: docker_host) if docker?
    scope = scope.where.not(id: id) if persisted?

    return unless scope.exists?

    msg = tcp? || redis? ? "is already monitored on port #{port} in this group" \
                         : "is already monitored in this group with the same probe type"
    errors.add(:address, msg)
  end

  def probe_type_immutable
    errors.add(:probe_type, "cannot be changed after the host is created") if probe_type_changed?
  end

  def address_must_be_valid_network_target
    return if address.blank?

    if (tcp? || redis?) && address.to_s.strip.match?(/\A[^:]+:\d+\z/)
      errors.add(:address, "should not include a port; enter the port in the Port field")
    elsif !NetworkAddress.valid?(address)
      errors.add(:address, "must be a hostname or IP address (for example 192.168.1.10 or nas.local)")
    end
  end

  def address_must_be_valid_domain_name
    return if address.blank? || NetworkAddress.hostname?(address)

    errors.add(:address, "must be a domain name (for example example.com)")
  end

  def address_must_be_valid_container
    return if address.blank? || address.match?(DOCKER_CONTAINER)

    errors.add(:address, "must be a container name or ID (for example nextcloud)")
  end

  def dns_server_must_be_an_ip_address
    return if dns_server.blank? || NetworkAddress.ip?(dns_server)

    errors.add(:dns_server, "must be an IP address (for example 1.1.1.1), or blank for the system resolver")
  end

  def docker_host_must_be_valid
    return if docker_endpoint

    errors.add(:docker_host, "must be unix:///path/to/docker.sock or tcp://host:port")
  end

  def timeout_must_be_shorter_than_interval
    return if timeout_seconds.blank? || interval.blank? || icmp? || push?
    return if timeout_seconds.to_i < interval.to_i

    errors.add(:timeout_seconds, "must be shorter than the interval")
  end

  def http_options_must_be_consistent
    if keyword.present? && http_method == "HEAD"
      errors.add(:keyword, "can't be checked with HEAD requests, which have no body")
    end
    if request_body.present? && !HTTP_METHODS_WITH_BODY.include?(http_method)
      errors.add(:request_body, "is only sent with #{HTTP_METHODS_WITH_BODY.to_sentence(last_word_connector: ' or ')}")
    end
    if request_headers.present? && request_headers.lines.any? { |line| line.strip.present? && !line.strip.match?(REQUEST_HEADER_LINE) }
      errors.add(:request_headers, "must be one \"Name: value\" per line")
    end
    if basic_auth_password.present? && basic_auth_user.blank?
      errors.add(:basic_auth_user, "is required with a password")
    end
  end

  def address_must_be_valid_http_url
    uri = URI.parse(normalized_http_address)
    if uri.host.blank? || !%w[http https].include?(uri.scheme)
      errors.add(:address, "must be a valid HTTP/HTTPS URL")
    end
  rescue URI::InvalidURIError
    errors.add(:address, "must be a valid HTTP/HTTPS URL")
  end

  def normalize_probe_specific_fields
    self.address = address.strip if address.is_a?(String)
    self.latency_threshold_ms = DEFAULT_LATENCY_THRESHOLD_MS if latency_threshold_ms.blank?
    self.timeout_seconds = 5 if timeout_seconds.blank?
    self.failure_threshold = DEFAULT_FAILURE_THRESHOLD if failure_threshold.blank?

    self.address = nil if push?
    self.port = DEFAULT_REDIS_PORT if redis? && port.blank?
    self.port = nil unless tcp? || redis?
    self.dns_server = dns_server.to_s.strip.presence
    self.dns_record_type = dns_record_type.to_s.strip.upcase.presence || "A"
    self.dns_expected_value = dns_expected_value.to_s.strip.presence
    self.docker_host = docker_host.to_s.strip.presence

    if redis?
      self.basic_auth_user = basic_auth_user.to_s.strip.presence
      self.basic_auth_password = basic_auth_password.presence
    end

    unless http?
      self.expected_status_code_range = "exact" if expected_status_code_range.blank?
      self.verify_ssl = true if verify_ssl.nil?
      return
    end

    self.expected_status_code = 200 if expected_status_code.blank?
    self.expected_status_code_range = "exact" if expected_status_code_range.blank?
    self.verify_ssl = true if verify_ssl.nil?
    self.http_method = http_method.to_s.strip.upcase.presence || "GET"
    self.max_redirects = 0 if max_redirects.blank?
    self.keyword = keyword.presence
    self.request_headers = request_headers.presence&.strip
    self.request_body = request_body.presence
    self.basic_auth_user = basic_auth_user.to_s.strip.presence
    # Clearing the username removes the stored password too (the form never shows it).
    self.basic_auth_password = nil if basic_auth_user.nil?
  end
end
