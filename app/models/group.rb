class Group < ApplicationRecord
  has_many :hosts, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :status_slug,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "must use lowercase letters, numbers, and hyphens" },
    allow_nil: true
  validates :status_slug, uniqueness: true, allow_nil: true
  validates :status_slug, presence: true, if: :is_public?

  scope :publicly_visible, -> { where(is_public: true) }

  before_validation :normalize_public_status_fields

  def public_status_path
    return unless is_public? && status_slug.present?

    "/status/#{status_slug}"
  end

  private

  def normalize_public_status_fields
    unless is_public?
      self.status_slug = nil
      return
    end

    self.status_slug = unique_slug_candidate if status_slug.blank?
  end

  def unique_slug_candidate
    base = name.to_s.parameterize.presence || "group"
    candidate = base
    suffix = 2

    while Group.where.not(id: id).exists?(status_slug: candidate)
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end

    candidate
  end
end
