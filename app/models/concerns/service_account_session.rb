# Turns the session record into something a machine can hold. A service account has no person
# behind it, so the host model must declare `belongs_to :user, optional: true` — the presence
# validation added here puts the requirement back for ordinary sessions only.
module ServiceAccountSession
  extend ActiveSupport::Concern

  included do
    validates :user, presence: true, unless: :service_account?

    # Signed bearer token (ActiveRecord::TokenFor) — verified against secret_key_base,
    # never stored in the database. Bound to created_at so a reused SQLite rowid can't
    # revive an old token; created_at is immutable, so the token lasts the session's life.
    # Revoke by destroying the session; rotate by creating a new one.
    generates_token_for :service_account_api do
      created_at.to_i
    end

    scope :service_accounts, -> { where(service_account: true) }
  end

  def service_account?
    service_account
  end
end
