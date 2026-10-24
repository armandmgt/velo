# A bike or a pair of shoes an Activity was done with. See CONTEXT.md.
class Gear < ApplicationRecord
  CATEGORY = { bike: :cycling, shoes: :running }.freeze

  belongs_to :user
  has_many :activities, dependent: :nullify
  has_many :gear_defaults, dependent: :delete_all
  has_many :components, class_name: "GearComponent", dependent: :destroy

  has_one_attached :photo

  enum :kind, %i[bike shoes].index_by(&:itself)

  attr_readonly :kind

  validates :name, :kind, presence: true
  validates :name, :brand, :model, length: { maximum: 80 }

  scope :active, -> { where(retired_at: nil) }
  scope :retired, -> { where.not(retired_at: nil) }

  after_save :sync_default_sports

  Totals = Struct.new(:distance, :moving_seconds, :elevation, :count)

  def self.kind_for_sport(sport)
    return if sport.blank?

    CATEGORY.key(Activity::SPORT_CATEGORY[sport.to_sym])&.to_s
  end

  def self.sports_for_kind(kind)
    Activity::SPORT_CATEGORY.select { |_sport, category| category == CATEGORY[kind.to_sym] }.keys.map(&:to_s)
  end

  def retired?
    retired_at.present?
  end

  def retire!
    update!(retired_at: Time.current)
  end

  def reactivate!
    update!(retired_at: nil)
  end

  def default_sports
    @default_sports || gear_defaults.map(&:sport)
  end

  def default_sports=(sports)
    @default_sports = Array(sports).compact_blank.map(&:to_s).uniq
  end

  def totals
    rows = activities.pluck(:distance, :active_time, :total_elevation_gain)
    Totals.new(
      rows.sum { |distance, _, _| distance.to_f },
      rows.sum { |_, active_time, _| DashboardStats.parse_seconds(active_time) },
      rows.sum { |_, _, elevation| elevation.to_f },
      rows.size
    )
  end

  private

  # Retired gear is never a default, and a sport has one default per user: the
  # gear just marked for it takes the sport over, as on Strava.
  def sync_default_sports
    return if @default_sports.nil? && !saved_change_to_retired_at?

    wanted = retired? ? [] : default_sports & self.class.sports_for_kind(kind)
    gear_defaults.where.not(sport: wanted).delete_all
    GearDefault.where(user_id: user_id, sport: wanted).where.not(gear_id: id).delete_all
    (wanted - gear_defaults.pluck(:sport)).each { |sport| gear_defaults.create!(user_id: user_id, sport: sport) }

    @default_sports = nil
    gear_defaults.reset
  end
end
