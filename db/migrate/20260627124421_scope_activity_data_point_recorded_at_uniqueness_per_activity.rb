class ScopeActivityDataPointRecordedAtUniquenessPerActivity < ActiveRecord::Migration[8.1]
  # The original table made `recorded_at` globally unique (`index: { unique: true }`).
  # That is wrong for a multi-user app: two different activities — even two
  # different users — recording at the same instant collide on insert. Scope the
  # uniqueness to the activity, which also matches the only access pattern
  # (an activity's points ordered by recorded_at) and subsumes the standalone
  # activity_id index (its leading column covers activity_id lookups + the FK).
  def up
    add_index :activity_data_points, %i[activity_id recorded_at], unique: true
    remove_index :activity_data_points, :recorded_at, name: "index_activity_data_points_on_recorded_at"
    remove_index :activity_data_points, :activity_id, name: "index_activity_data_points_on_activity_id"
  end

  def down
    add_index :activity_data_points, :activity_id, name: "index_activity_data_points_on_activity_id"
    add_index :activity_data_points, :recorded_at, unique: true, name: "index_activity_data_points_on_recorded_at"
    remove_index :activity_data_points, %i[activity_id recorded_at], unique: true
  end
end
