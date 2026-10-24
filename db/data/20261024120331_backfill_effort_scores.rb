# frozen_string_literal: true

# Scores every existing activity. Only riders with a max HR can have a score,
# and the work runs in jobs rather than inline.
class BackfillEffortScores < ActiveRecord::Migration[8.1]
  def up
    users = User.where.not(max_heart_rate: nil)
    users.find_each { |user| RecomputeEffortScoresJob.perform_later(user) }
    say "Enqueued effort score recompute for #{users.count} user(s)"
  end

  # Scores are derived data; the schema rollback drops them.
  def down; end
end
