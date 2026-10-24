# An address zone: a circle around a place the owner wants kept off every
# shared map (see "Hidden portion" in CONTEXT.md).
class MapPrivacyZone < ApplicationRecord
  RADIUS_OPTIONS = (200..1600).step(200).to_a.freeze

  belongs_to :user

  attribute :latitude, :float
  attribute :longitude, :float

  normalizes :name, with: ->(n) { n.strip.presence }

  validates :latitude, numericality: { in: -90..90 }
  validates :longitude, numericality: { in: -180..180 }
  validates :radius, inclusion: { in: RADIUS_OPTIONS }
  validates :name, length: { maximum: 50 }

  after_initialize do
    self.latitude ||= center&.y
    self.longitude ||= center&.x
  end

  before_save { self.center = "SRID=4326;POINT(#{longitude} #{latitude})" }
end
