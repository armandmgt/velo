class CreatePlannedRoutes < ActiveRecord::Migration[8.1]
  def change
    create_table :planned_routes do |t|
      t.references :user, null: false, foreign_key: true, index: true

      t.string :name, null: false
      t.string :sport, null: false
      t.jsonb :waypoints, null: false, default: []
      t.column :path, :geography, geographic: true, srid: 4326, type: :line_string
      t.integer :distance_meters
      t.integer :elevation_gain_meters
      t.string :routing_profile

      t.timestamps
    end
  end
end
