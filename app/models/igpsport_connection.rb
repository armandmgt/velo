class IgpsportConnection < ApplicationRecord
  belongs_to :user

  encrypts :email
  encrypts :password
  encrypts :access_token

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, :password, presence: true

  def token_valid?
    access_token.present? && (token_expires_at.nil? || token_expires_at.future?)
  end
end
