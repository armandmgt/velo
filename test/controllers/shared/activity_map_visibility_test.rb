require "test_helper"

# The security property of map visibility: a hidden coordinate must not appear
# anywhere in the share page — map values, route GeoJSON, chart or elevation
# data — so these tests scan every number in the rendered HTML.
class Shared::ActivityMapVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @activity = create_track(activities(:shareable))
    @owner = @activity.user
  end

  def numbers_in(body)
    body.scan(/-?\d+\.\d+/).map(&:to_f).to_set
  end

  def get_share_page
    get shared_activity_url(@activity.signed_id(purpose: :share))
    assert_response :success
    numbers_in(response.body)
  end

  def assert_hidden(numbers, indices)
    leaked = indices.select { numbers.include?(track_lat(it)) }
    assert_empty leaked, "hidden points leaked into the share page: #{leaked.inspect}"
  end

  def assert_shown(numbers, indices)
    missing = indices.reject { numbers.include?(track_lat(it)) }
    assert_empty missing, "visible points missing from the share page: #{missing.inspect}"
  end

  def summary_metrics
    css_select(".grid .text-2xl").map { it.text.strip }
  end

  test "by default hides 200 m along the track at each end" do
    numbers = get_share_page

    assert_hidden numbers, (0..4).to_a + (56..60).to_a
    assert_shown numbers, 5..55
  end

  test "the map opens on the visible geometry, not the track's first point" do
    get_share_page

    map = css_select("[data-controller=map]").first
    assert_not_equal track_lat(0), map["data-map-lat-value"].to_f
    assert_equal "LineString", JSON.parse(map["data-map-route-value"])["geometry"]["type"]
  end

  test "a distance of 0 shows the full track" do
    @owner.update!(map_hide_start_end_distance: 0)

    assert_shown get_share_page, 0..60
  end

  test "a distance of 1 km hides 1 km at each end" do
    @owner.update!(map_hide_start_end_distance: 1000)
    numbers = get_share_page

    assert_hidden numbers, (0..22).to_a + (38..60).to_a
    assert_shown numbers, 23..37
  end

  test "an address zone hides a mid-ride pass and splits the path around it" do
    @owner.update!(map_hide_start_end_distance: 0)
    @owner.map_privacy_zones.create!(latitude: track_lat(30), longitude: MapTrackHelper::LNG, radius: 200)
    numbers = get_share_page

    assert_hidden numbers, 26..34
    assert_shown numbers, (0..25).to_a + (35..60).to_a
    route = JSON.parse(css_select("[data-controller=map]").first["data-map-route-value"])
    assert_equal "MultiLineString", route["geometry"]["type"]
    assert_equal 2, route["geometry"]["coordinates"].size
  end

  test "masquer la carte removes the map and every coordinate while the stats remain" do
    login(@owner)
    get activity_url(@activity)
    owner_metrics = summary_metrics
    delete session_url

    @activity.update!(map_hidden: true)
    numbers = get_share_page

    assert_hidden numbers, 0..60
    assert_select "[data-controller=map]", false
    assert_select "[data-elevation-profile-coordinates-value]", false
    assert_select "[data-controller=elevation-profile]"
    assert_select "[data-controller=activity-charts]"
    assert_equal owner_metrics, summary_metrics
  end

  test "settings apply to an activity that was already shared" do
    @owner.update!(map_hide_start_end_distance: 0)
    assert_shown get_share_page, 30..30

    @owner.map_privacy_zones.create!(latitude: track_lat(30), longitude: MapTrackHelper::LNG, radius: 200)
    assert_hidden get_share_page, 30..30
  end

  test "a signed-in viewer other than the owner gets the trimmed page" do
    login(users(:one))

    assert_hidden get_share_page, 0..4
  end

  test "the owner's own activity page still shows the full track" do
    @owner.map_privacy_zones.create!(latitude: track_lat(30), longitude: MapTrackHelper::LNG, radius: 200)
    @activity.update!(map_hidden: true)
    login(@owner)

    get activity_url(@activity)

    assert_response :success
    assert_shown numbers_in(response.body), 0..60
    map = css_select("[data-controller=map]").first
    assert_equal track_lat(0), map["data-map-lat-value"].to_f
    assert_equal @activity.path_geojson, map["data-map-route-value"]
  end
end
