class Host < ApplicationRecord
  belongs_to :group
  has_many :pings, dependent: :destroy
  has_many :speed_tests, dependent: :destroy

  validates :name, presence: true
  validates :address, presence: true
  validates :interval, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 10 }

  def latest_ping
    pings.order(recorded_at: :desc).first
  end

  def status
    ping = latest_ping
    return :unknown if ping.nil?
    return :down if ping.packet_loss == 100
    return :degraded if ping.packet_loss.to_i >= 5
    :up
  end

  def speed_test_in_progress?
    speed_tests.where(status: [ SpeedTest.statuses[:queued], SpeedTest.statuses[:running] ]).exists?
  end

  def recent_speed_tests(limit = 5)
    speed_tests.recent.limit(limit)
  end
end
