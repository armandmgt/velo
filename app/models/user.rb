class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :planned_routes, dependent: :destroy
  has_one :igpsport_connection, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  generates_token_for :email_verification, expires_in: 1.day do
    email_address # invalidates the token if the address changes
  end

  validates :max_heart_rate,
            numericality: { only_integer: true, greater_than: 100, less_than_or_equal_to: 240 },
            allow_nil: true

  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update!(email_verified_at: Time.current)
  end
end
