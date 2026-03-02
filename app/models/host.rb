class Host < ApplicationRecord
  belongs_to :group
  has_many :pings, dependent: :destroy

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
end
