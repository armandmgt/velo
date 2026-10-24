class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :planned_routes, dependent: :destroy
  has_many :gears, dependent: :destroy
  has_many :gear_defaults, dependent: :delete_all
  has_one :igpsport_connection, dependent: :destroy
  has_many :map_privacy_zones, dependent: :destroy

  MAP_HIDE_DISTANCE_OPTIONS = (0..1600).step(200).to_a.freeze

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.strip.presence }

  generates_token_for :email_verification, expires_in: 1.day do
    email_address # invalidates the token if the address changes
  end

  validates :max_heart_rate,
            numericality: { only_integer: true, greater_than: 100, less_than_or_equal_to: 240 },
            allow_nil: true

  validates :ftp, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_000 }, allow_nil: true

  validates :name, length: { maximum: 50 }, allow_nil: true

  validates :map_hide_start_end_distance, inclusion: { in: MAP_HIDE_DISTANCE_OPTIONS }
  after_update_commit :recompute_effort_scores_later, if: -> { saved_change_to_max_heart_rate? || saved_change_to_ftp? }

  FTP_SUGGESTION_WINDOW = 6.months
  FTP_SUGGESTION_RATIO = 0.95

  after_update_commit -> { RefreshSegmentEffortPrivacyJob.perform_later(self) },
                      if: :saved_change_to_map_hide_start_end_distance?

  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update!(email_verified_at: Time.current)
  end

  # Coggan's estimate from the best 20-minute power of recent rides. Only ever
  # offered: Strava's own estimate is opaque and often optimistic, so the rider
  # decides whether to adopt it.
  def suggested_ftp
    best = BestEffort.kept.where(distance: "power_20m").joins(:activity)
      .where(activities: { user_id: id, start_time: FTP_SUGGESTION_WINDOW.ago.. })
      .maximum(:average_power)
    (best * FTP_SUGGESTION_RATIO).round if best
  end

  # Name to greet/display the user with. Falls back to a cleaned,
  # capitalized version of the email local-part when unset.
  def display_name
    name.presence || default_display_name
  end

  def default_gear_for(sport)
    gear_defaults.find_by(sport: sport)&.gear
  end

  def overdue_gear_components
    GearComponent.active.where(gear: gears.active).with_distance.includes(:gear).select(&:overdue?)
  end

  private

  def recompute_effort_scores_later
    RecomputeEffortScoresJob.perform_later(self)
  end

  def default_display_name
    local = email_address.to_s.split("@").first.to_s
    base = local.split(/[._+-]/).first
    base.present? ? base.capitalize : "cycliste"
  end
end
