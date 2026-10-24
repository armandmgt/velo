# frozen_string_literal: true

# Power analysis is computed at ingestion; rides that predate it get theirs from
# a job, since a Strava archive can mean thousands of activities.
class BackfillPowerAnalysis < ActiveRecord::Migration[8.1]
  def up
    BackfillPowerAnalysisJob.perform_later
  end

  def down; end
end
