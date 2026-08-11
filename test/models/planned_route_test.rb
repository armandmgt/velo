require "test_helper"

class PlannedRouteTest < ActiveSupport::TestCase
  test "ROUTABLE_SPORTS excludes non-routable Activity sports" do
    %i[virtual_ride virtual_run alpine_ski nordic_ski swim workout].each do |excluded|
      assert_not_includes PlannedRoute::ROUTABLE_SPORTS, excluded
    end
  end

  test "every routable sport maps to a BRouter profile" do
    PlannedRoute::ROUTABLE_SPORTS.each do |sport|
      assert PlannedRoute::BROUTER_PROFILE.key?(sport),
             "missing BRouter profile mapping for #{sport}"
    end
  end

  test "validates waypoints shape" do
    base = { user: users(:one), name: "x", sport: "bike" }
    assert PlannedRoute.new(base.merge(waypoints: [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [ [ 1.0, 2.0 ] ])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [ [ 200.0, 2.0 ], [ 3.0, 4.0 ] ])).valid?
    assert_not PlannedRoute.new(base.merge(waypoints: [ [ "a", 2.0 ], [ 3.0, 4.0 ] ])).valid?
  end

  # Waypoints ride in BRouter's GET query string, so the list needs a ceiling.
  test "accepts exactly MAX_WAYPOINTS waypoints" do
    waypoints = Array.new(PlannedRoute::MAX_WAYPOINTS) { |i| [ 2.0 + (i * 0.001), 48.0 ] }

    assert PlannedRoute.new(user: users(:one), name: "x", sport: "bike", waypoints: waypoints).valid?
  end

  test "rejects more than MAX_WAYPOINTS waypoints with a waypoint-specific message" do
    waypoints = Array.new(PlannedRoute::MAX_WAYPOINTS + 1) { |i| [ 2.0 + (i * 0.001), 48.0 ] }
    route = PlannedRoute.new(user: users(:one), name: "x", sport: "bike", waypoints: waypoints)

    assert_not route.valid?
    message = route.errors.full_messages_for(:waypoints).to_sentence
    assert_includes message, PlannedRoute::MAX_WAYPOINTS.to_s
    # The default :too_long message talks about characters, which is nonsense here.
    assert_not_includes message, "caractères"
  end

  test "sport_category and sport_icon_name delegate to Activity mapping" do
    pr = PlannedRoute.new(sport: "mountain_bike_ride")
    assert_equal :cycling, pr.sport_category
    assert_equal "bike", pr.sport_icon_name
  end

  test "path_geojson is nil without a path" do
    assert_nil PlannedRoute.new.path_geojson
  end

  test "elevation_chart_data returns nil without samples" do
    assert_nil PlannedRoute.new.elevation_chart_data
    assert_nil PlannedRoute.new(elevation_samples: []).elevation_chart_data
  end

  test "elevation_chart_data splits samples into labels and data arrays" do
    pr = PlannedRoute.new(elevation_samples: [ [ 0, 10 ], [ 111, 12 ], [ 222, 11 ] ])
    chart = pr.elevation_chart_data
    assert_equal [ 0, 111, 222 ], chart[:labels]
    assert_equal [ 10, 12, 11 ], chart[:data]
  end

  test "path_coordinates is empty without a path" do
    assert_equal [], PlannedRoute.new.path_coordinates
  end

  test "to_gpx emits a trk with trkpts and ele tags when samples are present" do
    pr = PlannedRoute.new(
      name: "Boucle test",
      sport: "bike",
      path: "SRID=4326;LINESTRING(2.35 48.85, 2.36 48.86, 2.37 48.87)",
      elevation_samples: [ [ 0, 100 ], [ 111, 110 ], [ 222, 105 ] ]
    )

    doc = Nokogiri::XML(pr.to_gpx)
    doc.remove_namespaces!

    assert_equal "Boucle test", doc.at_xpath("//trk/name").text
    assert_equal "bike",        doc.at_xpath("//trk/type").text

    trkpts = doc.xpath("//trkpt")
    assert_equal 3, trkpts.length
    assert_equal "48.85", trkpts[0]["lat"]
    assert_equal "2.35",  trkpts[0]["lon"]
    assert_equal %w[100 110 105], trkpts.map { |n| n.at_xpath("ele").text }
  end

  test "to_gpx omits ele when no elevation samples" do
    pr = PlannedRoute.new(
      name: "Sans altitude",
      sport: "run",
      path: "SRID=4326;LINESTRING(1.0 2.0, 1.1 2.1)",
      elevation_samples: nil
    )

    doc = Nokogiri::XML(pr.to_gpx)
    doc.remove_namespaces!

    assert_equal 2, doc.xpath("//trkpt").length
    assert_empty doc.xpath("//trkpt/ele")
  end

  test "to_gpx produces an empty trkseg when path is missing" do
    pr = PlannedRoute.new(name: "Vide", sport: "bike")

    doc = Nokogiri::XML(pr.to_gpx)
    doc.remove_namespaces!

    assert_not_nil doc.at_xpath("//trkseg")
    assert_empty doc.xpath("//trkpt")
  end
end
