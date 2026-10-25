require "test_helper"

class HeatmapsControllerTest < ActionDispatch::IntegrationTest
  # z12 tile over central Paris (lon 2.35, lat 48.85).
  PARIS_TILE = { z: 12, x: 2074, y: 1409 }.freeze
  PARIS_LINE = "LINESTRING(2.340 48.850, 2.345 48.852, 2.350 48.854)".freeze
  LYON_LINE = "LINESTRING(4.830 45.760, 4.835 45.762)".freeze

  setup do
    @user = users(:one)
    @other_user = users(:two)
    login(@user)
  end

  test "requires authentication" do
    delete session_url
    get heatmap_url
    assert_redirected_to new_session_url

    get tile_heatmap_url(**PARIS_TILE)
    assert_redirected_to new_session_url
  end

  test "renders the page fitted to the rider's activities" do
    create_activity(@user, path: PARIS_LINE)
    create_activity(@user, path: LYON_LINE)

    get heatmap_url

    assert_response :success
    bounds = JSON.parse(css_select("[data-controller=heatmap]").first["data-heatmap-bounds-value"])
    assert_in_delta 2.340, bounds[0][0], 1e-6
    assert_in_delta 45.760, bounds[0][1], 1e-6
    assert_in_delta 4.835, bounds[1][0], 1e-6
    assert_in_delta 48.854, bounds[1][1], 1e-6
  end

  test "the page's bounds and tile url follow the filters" do
    create_activity(@user, path: PARIS_LINE, sport: "run")
    create_activity(@user, path: LYON_LINE, sport: "bike")

    get heatmap_url(sport: "running")

    map = css_select("[data-controller=heatmap]").first
    bounds = JSON.parse(map["data-heatmap-bounds-value"])
    assert_in_delta 2.340, bounds[0][0], 1e-6
    assert_includes map["data-heatmap-tiles-url-value"], "/heatmap/tiles/{z}/{x}/{y}?sport=running"
  end

  test "a tile is a vector tile of the rider's own path" do
    create_activity(@user, path: PARIS_LINE)

    get tile_heatmap_url(**PARIS_TILE)

    assert_response :success
    assert_equal "application/vnd.mapbox-vector-tile", response.media_type
    assert_equal 1, feature_count(response.body)
  end

  test "every precomputed path band draws the path" do
    create_activity(@user, path: PARIS_LINE)

    Heatmap::TILE_PATH_ZOOMS.each do |z|
      get tile_heatmap_url(**tile_at(2.345, 48.852, z))
      assert_response :success
      assert_equal 1, feature_count(response.body), "no path in the z#{z} tile"
    end
  end

  test "a tile never carries another user's paths, whatever the parameters" do
    create_activity(@other_user, path: PARIS_LINE, sport: "bike")
    create_activity(@other_user, path: PARIS_LINE, sport: "run")
    create_activity(@user, path: LYON_LINE)

    crafted = [
      {},
      { user_id: @other_user.id },
      { user: { id: @other_user.id } },
      { sport: "cycling' OR 1=1 --" },
      { sport: [ "cycling", "running" ] },
      { period: "custom", from: "2000-01-01' OR '1'='1", to: "2999-01-01" },
      { period: "1' OR 1=1 --" }
    ]
    crafted.each do |params|
      get tile_heatmap_url(**PARIS_TILE, **params)
      assert_response :success
      assert_equal 0, feature_count(response.body), "leaked another user's path with #{params.inspect}"
    end
  end

  test "the sport category filter selects which paths appear" do
    create_activity(@user, path: PARIS_LINE, sport: "gravel_ride")
    create_activity(@user, path: PARIS_LINE, sport: "trail_run")
    create_activity(@user, path: PARIS_LINE, sport: "walk")

    assert_equal 3, tile_features
    assert_equal 1, tile_features(sport: "cycling")
    assert_equal 2, tile_features(sport: "running")
    assert_equal 0, tile_features(sport: "other")
    assert_equal 3, tile_features(sport: "unknown")
  end

  test "the date range filter selects which paths appear" do
    create_activity(@user, path: PARIS_LINE, start_time: Time.zone.local(2024, 3, 1, 9))
    create_activity(@user, path: PARIS_LINE, start_time: Time.zone.local(2025, 6, 15, 9))
    create_activity(@user, path: PARIS_LINE, start_time: Time.zone.local(2025, 12, 31, 18))

    assert_equal 3, tile_features
    assert_equal 2, tile_features(period: "2025")
    assert_equal 1, tile_features(period: "2024")
    assert_equal 1, tile_features(period: "custom", from: "2025-06-01", to: "2025-06-30")
    assert_equal 2, tile_features(period: "custom", from: "2025-06-15")
    assert_equal 2, tile_features(period: "custom", to: "2025-06-15")
    assert_equal 3, tile_features(period: "custom", from: "not-a-date")
  end

  test "paths stored without an SRID still render" do
    activity = create_activity(@user, path: PARIS_LINE)
    Activity.where(id: activity.id).update_all("path = ST_SetSRID(path, 0)")

    assert_equal 1, tile_features
  end

  test "rejects tiles outside the pyramid" do
    get tile_heatmap_url(z: 3, x: 8, y: 0)
    assert_response :bad_request

    get tile_heatmap_url(z: Heatmap::MAX_ZOOM + 1, x: 0, y: 0)
    assert_response :bad_request
  end

  test "an unchanged tile revalidates, and a new activity invalidates it" do
    with_cache_store do
      get tile_heatmap_url(**PARIS_TILE)
      assert_equal 0, feature_count(response.body)
      etag = response.headers["ETag"]

      get tile_heatmap_url(**PARIS_TILE), headers: { "If-None-Match" => etag }
      assert_response :not_modified

      activity = create_activity(@user, path: PARIS_LINE)
      get tile_heatmap_url(**PARIS_TILE), headers: { "If-None-Match" => etag }
      assert_response :success
      assert_equal 1, feature_count(response.body)

      activity.update!(path: "SRID=4326;#{LYON_LINE}")
      assert_equal 0, tile_features

      activity.update!(path: "SRID=4326;#{PARIS_LINE}")
      assert_equal 1, tile_features

      activity.destroy!
      assert_equal 0, tile_features
    end
  end

  private
    def create_activity(user, path:, sport: "bike", start_time: Time.zone.local(2025, 5, 1, 9))
      user.activities.create!(
        name: "Sortie", sport:, start_time:, end_time: start_time + 1.hour,
        location: "Paris", active_time: "PT3600S", path: "SRID=4326;#{path}"
      )
    end

    def tile_features(**params)
      get tile_heatmap_url(**PARIS_TILE, **params)
      assert_response :success
      feature_count(response.body)
    end

    def tile_at(lon, lat, z)
      lat_rad = lat * Math::PI / 180
      {
        z:,
        x: ((lon + 180) / 360 * 2**z).floor,
        y: ((1 - Math.log(Math.tan(lat_rad) + 1 / Math.cos(lat_rad)) / Math::PI) / 2 * 2**z).floor
      }
    end

    def with_cache_store
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end

    # Counts features in an MVT tile: Tile.layers (field 3) → Layer.features (field 2).
    def feature_count(tile)
      each_field(tile.b).sum do |field, layer|
        field == 3 ? each_field(layer).count { |inner, _| inner == 2 } : 0
      end
    end

    def each_field(bytes)
      Enumerator.new do |fields|
        io = StringIO.new(bytes)
        until io.eof?
          key = read_varint(io)
          case key & 0x7
          when 0 then fields << [ key >> 3, read_varint(io) ]
          when 1 then fields << [ key >> 3, io.read(8) ]
          when 2 then fields << [ key >> 3, io.read(read_varint(io)) ]
          when 5 then fields << [ key >> 3, io.read(4) ]
          else raise "unexpected protobuf wire type #{key & 0x7}"
          end
        end
      end
    end

    def read_varint(io)
      value = shift = 0
      loop do
        byte = io.readbyte
        value |= (byte & 0x7f) << shift
        return value if byte < 0x80
        shift += 7
      end
    end
end
