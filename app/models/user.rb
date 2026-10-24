class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :planned_routes, dependent: :destroy
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

  validates :name, length: { maximum: 50 }, allow_nil: true

  validates :map_hide_start_end_distance, inclusion: { in: MAP_HIDE_DISTANCE_OPTIONS }

  after_update_commit -> { RefreshSegmentEffortPrivacyJob.perform_later(self) },
                      if: :saved_change_to_map_hide_start_end_distance?

  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update!(email_verified_at: Time.current)
  end

  # Name to greet/display the user with. Falls back to a cleaned,
  # capitalized version of the email local-part when unset.
  def display_name
    name.presence || default_display_name
  end

  private

  def default_display_name
    local = email_address.to_s.split("@").first.to_s
    base = local.split(/[._+-]/).first
    base.present? ? base.capitalize : "cycliste"
  end
end
