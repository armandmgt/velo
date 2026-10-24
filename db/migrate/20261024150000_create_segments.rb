class CreateSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :segments do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.string :sport_category, null: false
      t.geography :path, limit: { srid: 4326, type: "line_string", geographic: true }, null: false
      t.geography :start_point, limit: { srid: 4326, type: "st_point", geographic: true }, null: false
      t.geography :end_point, limit: { srid: 4326, type: "st_point", geographic: true }, null: false
      t.float :altitudes, array: true, null: false, default: []
      t.float :distance, null: false
      t.float :elevation_gain, null: false, default: 0
      t.float :average_grade, null: false, default: 0
      t.timestamps
    end

    add_index :segments, :path, using: :gist
    add_index :segments, :start_point, using: :gist
    add_index :segments, :end_point, using: :gist

    create_table :segment_efforts do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }
      t.references :activity, null: false, foreign_key: { on_delete: :cascade }
      t.integer :start_index, null: false
      t.integer :end_index, null: false
      t.float :elapsed_seconds, null: false
      t.boolean :private, null: false, default: false
      t.integer :rank
      t.timestamps
    end

    add_index :segment_efforts, %i[segment_id elapsed_seconds], where: "NOT private", name: "index_segment_efforts_on_leaderboard"

    # A new segment's backfill looks for activities passing near its start and end.
    add_index :activities, "(path::geography)", using: :gist, name: "index_activities_on_path_geography"
  end
end
