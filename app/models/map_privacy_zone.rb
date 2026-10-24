# An address zone: a circle around a place the owner wants kept off every
# shared map (see "Hidden portion" in CONTEXT.md).
class MapPrivacyZone < ApplicationRecord
  RADIUS_OPTIONS = (200..1600).step(200).to_a.freeze

  belongs_to :user

  attribute :latitude, :float
  attribute :longitude, :float

  normalizes :name, with: ->(n) { n.strip.presence }

  validate :center_chosen
  validates :radius, inclusion: { in: RADIUS_OPTIONS }
  validates :name, length: { maximum: 50 }

  after_initialize do
    self.latitude ||= center&.y
    self.longitude ||= center&.x
  end

  before_save { self.center = "SRID=4326;POINT(#{longitude} #{latitude})" }
  after_commit { RefreshSegmentEffortPrivacyJob.perform_later(user) }

  private

  def center_chosen
    return if latitude&.between?(-90, 90) && longitude&.between?(-180, 180)

    errors.add(:latitude, "doit être choisi sur la carte")
  end
end
