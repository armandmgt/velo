# Heatmap tiles read paths already in Web Mercator, one column per zoom band,
# named after the band's deepest zoom and simplified to one 512 px display pixel
# there. The z14 band is only simplified to the z14 tile grid, which is all a
# tile can hold. Generated, so they backfill here and can't drift from `path`.
# Older activities stored their path without an SRID; every path is lon/lat.
class AddHeatmapTilePathsToActivities < ActiveRecord::Migration[8.1]
  WORLD_METERS = 40_075_016.685_578_49
  TOLERANCES = {
    tile_path_z7: WORLD_METERS / 2**7 / 512,
    tile_path_z9: WORLD_METERS / 2**9 / 512,
    tile_path_z11: WORLD_METERS / 2**11 / 512,
    tile_path_z13: WORLD_METERS / 2**13 / 512,
    tile_path_z14: WORLD_METERS / 2**14 / 4096
  }.transform_values { it.round(1) }.freeze

  def change
    change_table :activities, bulk: true do |t|
      TOLERANCES.each do |column, tolerance|
        t.virtual column, type: :line_string, srid: 3857, stored: true,
          as: "ST_Simplify(ST_Transform(ST_SetSRID(path, 4326), 3857), #{tolerance})"
      end
    end
    TOLERANCES.each_key { |column| add_index :activities, column, using: :gist }
  end
end
