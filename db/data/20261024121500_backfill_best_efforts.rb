# frozen_string_literal: true

# Best efforts are computed at ingestion; activities that predate them get
# theirs from a job, since a Strava archive can mean thousands of activities.
class BackfillBestEfforts < ActiveRecord::Migration[8.1]
  def up
    BackfillBestEffortsJob.perform_later
  end

  def down; end
end
