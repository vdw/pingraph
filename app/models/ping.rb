class Ping < ApplicationRecord
  belongs_to :host

  validates :packet_loss, presence: true
  validates :recorded_at, presence: true
end
