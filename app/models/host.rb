class Host < ApplicationRecord
  DEFAULT_LATENCY_THRESHOLD_MS = 350.0

  belongs_to :group
  has_many :probe_results, dependent: :destroy
  has_many :speed_tests, dependent: :destroy

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
  validate :probe_type_immutable, on: :update

  before_validation :normalize_probe_specific_fields

  def latest_probe_result
    probe_results.order(recorded_at: :desc).first
  end

  def status_badge
    result = latest_probe_result
    return :unknown if result.nil?
    return :down if status == "down"
    return :degraded if result_degraded?(result)
    return :degraded unless result.success?

    :up
  end

  def result_degraded?(result)
    return false if result.nil?
    success = result.respond_to?(:success?) ? result.success? : result.success
    icmp_result = result.respond_to?(:icmp?) ? result.icmp? : result.probe_type.to_s == "icmp"

    return true unless success
    return true if icmp_result && result.packet_loss.to_i >= 5

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
    speed_tests.where(status: [ SpeedTest.statuses[:queued], SpeedTest.statuses[:running] ]).exists?
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

  def address_must_be_valid_http_url
    uri = URI.parse(normalized_http_address)
    if uri.host.blank? || !%w[http https].include?(uri.scheme)
      errors.add(:address, "must be a valid HTTP/HTTPS URL")
    end
  rescue URI::InvalidURIError
    errors.add(:address, "must be a valid HTTP/HTTPS URL")
  end

  def normalize_probe_specific_fields
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
