class CreateActivityDataPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_data_points do |t|
      t.belongs_to :activity, foreign_key: true, null: false
      t.datetime :recorded_at, index: { unique: true }, null: false
      t.decimal :speed
      t.integer :heart_rate
      t.decimal :cadence
      t.decimal :power
      t.float :latitude
      t.float :longitude
      t.timestamps
    end
  end
end