class Host < ApplicationRecord
  DEFAULT_LATENCY_THRESHOLD_MS = 350.0
  # A sample counts as a problem at 2 of 5 lost packets; a single dropped packet is noise.
  DEGRADED_PACKET_LOSS_PERCENT = 40
  # Consecutive problem samples (failed, slow or lossy) before the host turns Degraded.
  DEGRADED_THRESHOLD = 2

  belongs_to :group
  # delete_all: one DELETE statement instead of instantiating ~130k rows per busy host.
  has_many :probe_results, dependent: :delete_all
  has_many :speed_tests, dependent: :delete_all
  has_many :notification_deliveries, dependent: :nullify

  enum :probe_type, {
    icmp: 0,
    http: 1,
    tcp: 2
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
  validates :address, presence: true
  validate :address_unique_within_group
  validates :interval, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 10 }
  validates :latency_threshold_ms, numericality: { greater_than: 0 }
  validates :port, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535 }, if: :tcp?
  validates :expected_status_code, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 599 }, if: :http?
  validates :expected_status_code_range, inclusion: { in: %w[exact 2xx 3xx 4xx 5xx] }, if: :http?
  validates :verify_ssl, inclusion: { in: [ true, false ] }, if: :http?

  validate :address_must_be_valid_http_url, if: :http?
  validate :address_must_be_valid_network_target, unless: :http?
  validate :probe_type_immutable, on: :update

  before_validation :normalize_probe_specific_fields
  # A new interval takes effect on the next poller run instead of after the old one.
  before_save -> { self.next_probe_at = nil }, if: :interval_changed?

  def latest_probe_result
    probe_results.order(recorded_at: :desc).first
  end

  # The persisted status is computed by ProbeService from consecutive samples, so a single
  # bad sample does not flip the badge (and no extra query is needed per host).
  def status_badge
    status.to_sym
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

  def normalized_http_address
    value = address.to_s.strip
    return value if value.start_with?("http://", "https://")

    "https://#{value}"
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
    return if address.blank? || group_id.blank?

    scope = Host.where(group_id: group_id, address: address, probe_type: probe_type)
    scope = scope.where(port: port) if tcp?
    scope = scope.where.not(id: id) if persisted?

    return unless scope.exists?

    msg = tcp? ? "is already monitored on port #{port} in this group" \
                : "is already monitored in this group with the same probe type"
    errors.add(:address, msg)
  end

  def probe_type_immutable
    errors.add(:probe_type, "cannot be changed after the host is created") if probe_type_changed?
  end

  def address_must_be_valid_network_target
    return if address.blank?

    if tcp? && address.to_s.strip.match?(/\A[^:]+:\d+\z/)
      errors.add(:address, "should not include a port; enter the port in the Port field")
    elsif !NetworkAddress.valid?(address)
      errors.add(:address, "must be a hostname or IP address (for example 192.168.1.10 or nas.local)")
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

    if tcp?
      self.expected_status_code_range = "exact" if expected_status_code_range.blank?
      self.verify_ssl = true if verify_ssl.nil?
      return
    end

    self.port = nil

    return unless http?

    self.expected_status_code = 200 if expected_status_code.blank?
    self.expected_status_code_range = "exact" if expected_status_code_range.blank?
    self.verify_ssl = true if verify_ssl.nil?
  end
end
