require "test_helper"

class MapVisibilityTest < ActiveSupport::TestCase
  setup do
    @activity = create_track(activities(:shareable))
    @owner = @activity.user
  end

  def visible_lats(visibility)
    visibility.coordinates.compact.map(&:last)
  end

  test "the owner sees every point and the stored path" do
    visibility = MapVisibility.new(@activity, viewer: @owner)

    assert_equal 61, visibility.coordinates.compact.size
    assert_equal @activity.path_geojson, visibility.path_geojson
    assert_equal [ MapTrackHelper::LNG, track_lat(0) ], visibility.center
  end

  test "hides 200 m along the track at each end by default" do
    visibility = MapVisibility.new(@activity, viewer: nil)

    assert_equal (5..55).map { track_lat(it) }, visible_lats(visibility)
    assert_equal (5..55).to_a, visibility.visible_indices
  end

  test "another signed-in user is treated like an anonymous viewer" do
    visibility = MapVisibility.new(@activity, viewer: users(:one))

    assert_equal (5..55).map { track_lat(it) }, visible_lats(visibility)
  end

  test "a distance of 0 shows the full track" do
    @owner.update!(map_hide_start_end_distance: 0)

    assert_equal 61, MapVisibility.new(@activity, viewer: nil).coordinates.compact.size
  end

  test "a distance of 1 km hides 1 km at each end" do
    @owner.update!(map_hide_start_end_distance: 1000)

    assert_equal (23..37).map { track_lat(it) }, visible_lats(MapVisibility.new(@activity, viewer: nil))
  end

  test "a track shorter than both trims shows no map" do
    @owner.update!(map_hide_start_end_distance: 1600)
    visibility = MapVisibility.new(@activity, viewer: nil)

    assert_empty visibility.coordinates.compact
    assert_not visibility.show_map?
    assert_nil visibility.path_geojson
  end

  test "an address zone hides a mid-ride pass and splits the path around it" do
    @owner.update!(map_hide_start_end_distance: 0)
    @owner.map_privacy_zones.create!(latitude: track_lat(30), longitude: MapTrackHelper::LNG, radius: 200)
    visibility = MapVisibility.new(@activity, viewer: nil)

    assert_equal ((0..25).to_a + (35..60).to_a).map { track_lat(it) }, visible_lats(visibility)

    geometry = JSON.parse(visibility.path_geojson)["geometry"]
    assert_equal "MultiLineString", geometry["type"]
    assert_equal [ (0..25).map { track_lat(it) }, (35..60).map { track_lat(it) } ],
                 geometry["coordinates"].map { |line| line.map(&:last) }
  end

  test "another user's zones don't apply" do
    @owner.update!(map_hide_start_end_distance: 0)
    users(:one).map_privacy_zones.create!(latitude: track_lat(30), longitude: MapTrackHelper::LNG, radius: 200)

    assert_equal 61, MapVisibility.new(@activity, viewer: nil).coordinates.compact.size
  end

  test "hiding the map withholds every coordinate but keeps the chart series" do
    @activity.update!(map_hidden: true)
    visibility = MapVisibility.new(@activity, viewer: nil)

    assert visibility.map_hidden?
    assert_not visibility.show_map?
    assert_equal Array.new(61), visibility.chart_data[:coordinates]
    assert_equal Array.new(61), visibility.elevation_chart_data[:coordinates]
    assert_equal 61, visibility.chart_data[:datasets].first[:data].compact.size
    assert_equal 61, visibility.elevation_chart_data[:data].compact.size
  end

  test "hiding the map doesn't affect the owner" do
    @activity.update!(map_hidden: true)

    assert MapVisibility.new(@activity, viewer: @owner).show_map?
  end

  test "the map opens on the visible geometry, not the first point" do
    assert_equal [ MapTrackHelper::LNG, track_lat(5) ], MapVisibility.new(@activity, viewer: nil).center
  end

  test "chart coordinates stay index-aligned with the chart series" do
    visibility = MapVisibility.new(@activity, viewer: nil)
    data = visibility.chart_data

    assert_equal data[:labels].size, data[:coordinates].size
    assert_nil data[:coordinates][4]
    assert_equal [ MapTrackHelper::LNG, track_lat(5) ], data[:coordinates][5]
  end
end
