class CreateActivityDataPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_data_points do |t|
      t.belongs_to :activity, foreign_key: true, null: false

      t.datetime :recorded_at, index: { unique: true }, null: false
      t.st_point :location, geographic: true
      t.decimal :speed
      t.integer :heart_rate
      t.decimal :cadence
      t.decimal :power

      t.timestamps
    end
  end
end
