class Group < ApplicationRecord
  has_many :hosts, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
