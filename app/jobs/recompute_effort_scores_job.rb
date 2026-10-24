# Every heart-rate effort score depends on the rider's max HR, so changing it
# (or the initial backfill) rescores all of their activities.
class RecomputeEffortScoresJob < ApplicationJob
  queue_as :default

  def perform(user)
    user.activities.find_each(&:recompute_effort_score!)
  end
end
