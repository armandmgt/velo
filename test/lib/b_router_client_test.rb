require "test_helper"

class BRouterClientTest < ActiveSupport::TestCase
  test "parses a successful GeoJSON FeatureCollection into a Route" do
    body = {
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          geometry: { type: "LineString", coordinates: [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ] },
          properties: { "track-length" => "1234", "filtered ascend" => "42" }
        }
      ]
    }.to_json

    with_brouter_response(success_response(body)) do
      route = BRouterClient.new.route(waypoints: [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ], profile: "safety")
      assert_equal [ [ 2.35, 48.85 ], [ 2.36, 48.86 ] ], route.coordinates
      assert_equal 1234, route.distance_meters
      assert_equal 42, route.elevation_gain_meters
    end
  end

  test "raises NoRouteFound when the body starts with 'no track found'" do
    with_brouter_response(success_response("no track found, lonlats too far apart")) do
      assert_raises(BRouterClient::NoRouteFound) do
        BRouterClient.new.route(waypoints: [ [ 0.0, 0.0 ], [ 1.0, 1.0 ] ], profile: "safety")
      end
    end
  end

  test "raises Error on non-success response codes" do
    with_brouter_response(failure_response("upstream error", code: 502)) do
      assert_raises(BRouterClient::Error) do
        BRouterClient.new.route(waypoints: [ [ 0.0, 0.0 ], [ 1.0, 1.0 ] ], profile: "safety")
      end
    end
  end

  private

  def with_brouter_response(response)
    BRouterClient.define_singleton_method(:get) { |_path, **_opts| response }
    yield
  ensure
    if BRouterClient.singleton_class.instance_methods(false).include?(:get)
      BRouterClient.singleton_class.remove_method(:get)
    end
  end

  def success_response(body)
    FakeResponse.new(body: body, code: 200, success: true)
  end

  def failure_response(body, code:)
    FakeResponse.new(body: body, code: code, success: false)
  end

  FakeResponse = Struct.new(:body, :code, :success, keyword_init: true) do
    def success?
      success
    end

    def parsed_response
      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
