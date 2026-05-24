class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_one :igpsport_connection, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :max_heart_rate,
            numericality: { only_integer: true, greater_than: 100, less_than_or_equal_to: 240 },
            allow_nil: true
end
