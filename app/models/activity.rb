class Activity < ApplicationRecord
  include ActivityCharts
  include ActivityMetrics
  include ActivityHeartRateZones

  belongs_to :user
  belongs_to :gear, optional: true
  has_many :activity_data_points, dependent: :destroy

  has_one_attached :source_file

  enum :sport, %i[
    bike mountain_bike_ride gravel_ride virtual_ride e_bike_ride
    run trail_run virtual_run walk
    hike alpine_ski nordic_ski swim workout
  ].index_by(&:itself)

  enum :visibility, %i[private shareable public].index_by(&:itself), prefix: true

  SPORT_CATEGORY = {
    bike: :cycling, mountain_bike_ride: :cycling, gravel_ride: :cycling,
    virtual_ride: :cycling, e_bike_ride: :cycling,
    run: :running, trail_run: :running, virtual_run: :running, walk: :running,
    hike: :other, alpine_ski: :other, nordic_ski: :other, swim: :other, workout: :other
  }.freeze

  validates :name, :sport, :start_time, :end_time, presence: true
  validate :gear_belongs_to_owner

  # A swim can't have been done on a bike: changing the sport to one the gear
  # doesn't fit drops the gear rather than keep a contradiction.
  before_validation :drop_gear_of_another_kind

  scope :awaiting_name, -> { where(name_pending: true) }

  # Keep every page the owner has open (dashboard + activities list, including
  # the native tabs) in sync without a manual reload. On any create / update /
  # destroy — direct upload, edit, or a background iGPSport/Strava import — push
  # a Turbo morph page-refresh to the owner's stream. Because the layout sets
  # `turbo-refresh-method: morph`, the subscribed page re-renders server-side and
  # morphs in place, so stats, records and lists all refresh together. The
  # `_later` variant coalesces the burst of broadcasts a bulk sync emits.
  after_commit :broadcast_activity_refresh

  def broadcast_activity_refresh
    broadcast_refresh_later_to(user, :activities)
  end

  def path_geojson
    return unless path
    {
      type: "Feature",
      geometry: {
        type: "LineString",
        properties: {},
        coordinates: path.points.map do |point|
          [ point.x, point.y ]
        end
      }
    }.to_json
  end

  def active_time_duration
    ActiveSupport::Duration.parse(active_time)
  end

  def duration
    ActiveSupport::Duration.build((end_time - start_time).to_i)
  end

  def sport_category
    SPORT_CATEGORY.fetch(sport.to_sym)
  end

  def sport_icon_name
    { cycling: "bike", running: "sport-shoe", other: "zap" }.fetch(sport_category)
  end

  def shareable_link?
    visibility_shareable? || visibility_public?
  end

  private

  def gear_belongs_to_owner
    errors.add(:gear, :invalid) if gear && gear.user_id != user_id
  end

  def drop_gear_of_another_kind
    self.gear = nil if gear && sport.present? && Gear.kind_for_sport(sport) != gear.kind
  end
end
