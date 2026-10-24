class AddEffortScoreToActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :effort_score, :decimal, precision: 7, scale: 1
    add_column :activities, :effort_score_source, :string
  end
end
