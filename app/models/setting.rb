class Setting < ApplicationRecord
  RETENTION_OPTIONS = [ 30, 60, 90 ].freeze
  DEFAULT_RETENTION_DAYS = 90

  alias_attribute :ping_retention_days, :probe_result_retention_days

  validates :probe_result_retention_days, inclusion: { in: RETENTION_OPTIONS }

  def self.current
    first_or_create!(probe_result_retention_days: DEFAULT_RETENTION_DAYS)
  end
end
