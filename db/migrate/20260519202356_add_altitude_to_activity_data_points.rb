class AddAltitudeToActivityDataPoints < ActiveRecord::Migration[8.1]
  def change
    add_column :activity_data_points, :altitude, :decimal
  end
end
