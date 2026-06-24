# frozen_string_literal: true

# Marks every pre-existing user as email-verified. These accounts predate the
# email-verification gate, so without this backfill they would be unable to log
# in. Only touches users that aren't already verified; new signups go through
# the real verification flow.
class BackfillEmailVerifiedAt < ActiveRecord::Migration[8.1]
  def up
    count = User.where(email_verified_at: nil).update_all(email_verified_at: Time.current)
    say "Marked #{count} existing user(s) as email-verified"
  end

  # Verification status is not something we want to revoke on rollback.
  def down; end
end
