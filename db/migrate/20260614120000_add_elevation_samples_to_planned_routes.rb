class AddElevationSamplesToPlannedRoutes < ActiveRecord::Migration[8.1]
  def change
    add_column :planned_routes, :elevation_samples, :jsonb
  end
end
