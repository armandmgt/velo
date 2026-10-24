# A wearing part of a bike, tracked against a service interval. See CONTEXT.md.
class GearComponent < ApplicationRecord
  WARNING_RATIO = 0.9

  # Install dates are the rider's calendar days, not UTC ones.
  ZONE = "Europe/Paris".freeze

  belongs_to :gear

  enum :kind, %i[chain cassette tires brake_pads drivetrain custom].index_by(&:itself), scopes: false

  validates :kind, :installed_on, presence: true
  validates :nickname, presence: true, if: :custom?
  validates :nickname, length: { maximum: 80 }
  validates :service_interval_km, numericality: { only_integer: true, greater_than: 0 }
  validate :gear_is_a_bike

  scope :active, -> { where(retired_at: nil) }
  scope :retired, -> { where.not(retired_at: nil) }

  # Distance is the bike's activities from the install day on — computed in SQL
  # so the bell can rank every component of every bike in one query.
  scope :with_distance, -> {
    select(arel_table[Arel.star], <<~SQL.squish)
      COALESCE((
        SELECT SUM(activities.distance) FROM activities
        WHERE activities.gear_id = gear_components.gear_id
          AND activities.start_time >=
            (gear_components.installed_on::timestamp AT TIME ZONE '#{ZONE}') AT TIME ZONE 'UTC'
      ), 0) AS distance_since_install
    SQL
  }

  def name
    custom? ? nickname : I18n.t("gear_component.kind.#{kind}")
  end

  def retired?
    retired_at.present?
  end

  # Meters. A retired component is frozen at the distance it had when replaced.
  def distance
    return final_distance.to_f if retired?
    return self[:distance_since_install].to_f if has_attribute?(:distance_since_install)

    self.class.with_distance.find(id).distance
  end

  def progress
    distance / 1000.0 / service_interval_km
  end

  def status
    return :overdue if progress > 1
    return :warning if progress >= WARNING_RATIO

    :ok
  end

  def overdue?
    !retired? && status == :overdue
  end

  # The old component keeps its history; the new one starts counting from its
  # own install date.
  def replace!(installed_on: Date.current)
    transaction do
      update!(retired_at: Time.current, final_distance: distance)
      gear.components.create!(kind: kind, nickname: nickname,
                              service_interval_km: service_interval_km, installed_on: installed_on)
    end
  end

  private

  def gear_is_a_bike
    errors.add(:gear, :invalid) if gear && !gear.bike?
  end
end
