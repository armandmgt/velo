class AddActivityFields < ActiveRecord::Migration[8.1]
  def change
    change_table :activities, bulk: true do |t|
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.string :location, null: false
      t.decimal :distance
      t.string :active_time, null: false
      t.decimal :total_elevation_gain
      t.decimal :max_speed
    end
  end
end
