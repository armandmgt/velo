class CreateMapPrivacyZones < ActiveRecord::Migration[8.1]
  def change
    create_table :map_privacy_zones do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.st_point :center, geographic: true, srid: 4326, null: false
      t.integer :radius, null: false, default: 200
      t.timestamps
    end
  end
end
