class SpeedTest < ApplicationRecord
  belongs_to :host

  enum :status, {
    queued: 0,
    running: 1,
    completed: 2
  }, default: :queued

  scope :recent, -> { order(recorded_at: :desc, created_at: :desc) }

  validates :protocol, presence: true
  validates :bandwidth_mbps, :recorded_at, presence: true, if: :completed?
end
