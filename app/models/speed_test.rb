class SpeedTest < ApplicationRecord
  # A test that is still queued/running after this long was lost (worker restart, crash)
  # and must stop blocking new tests for its host.
  STALE_AFTER = 5.minutes

  belongs_to :host

  enum :status, {
    queued: 0,
    running: 1,
    completed: 2,
    failed: 3
  }, default: :queued

  scope :recent, -> { order(recorded_at: :desc, created_at: :desc) }
  scope :in_progress, -> { where(status: [ statuses[:queued], statuses[:running] ]) }

  validates :protocol, presence: true
  validates :bandwidth_mbps, :recorded_at, presence: true, if: :completed?

  def self.fail_stale!(now: Time.current)
    in_progress.where(updated_at: ...(now - STALE_AFTER)).update_all(
      status: statuses[:failed],
      error_message: "Timed out: the test never finished (the background worker may have restarted)",
      recorded_at: now,
      updated_at: now
    )
  end

  def fail!(message)
    update!(status: :failed, error_message: message.to_s.truncate(500), recorded_at: Time.current)
  end
end
