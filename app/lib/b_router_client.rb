class BRouterClient
  include HTTParty

  base_uri "https://brouter.de"
  headers "User-Agent" => "Velo"
  default_timeout 15

  class Error < StandardError; end
  class NoRouteFound < Error; end

  Route = Data.define(:coordinates, :distance_meters, :elevation_gain_meters)

  # waypoints: Array<[lon, lat]>, profile: String (BRouter profile name).
  # Returns a Route Data struct or raises.
  def route(waypoints:, profile:)
    lonlats = waypoints.map { |lon, lat| "#{lon},#{lat}" }.join("|")

    response = self.class.get(
      "/brouter",
      query: {
        lonlats:        lonlats,
        profile:        profile,
        alternativeidx: 0,
        format:         "geojson"
      }
    )

    raise NoRouteFound, response.body.to_s if response.body.to_s.start_with?("no track found")
    raise Error, "BRouter request failed (#{response.code}): #{response.body}" unless response.success?

    # BRouter serves GeoJSON with Content-Type application/vnd.geo+json, which
    # HTTParty doesn't auto-parse. Parse the body ourselves.
    payload = JSON.parse(response.body)
    feature = payload.fetch("features").first
    raise NoRouteFound, "BRouter returned no features" unless feature

    coords = feature.fetch("geometry").fetch("coordinates")
    props  = feature.fetch("properties")

    Route.new(
      coordinates:           coords.map { |c| [ c[0].to_f, c[1].to_f ] },
      distance_meters:       props["track-length"].to_i,
      elevation_gain_meters: props["filtered ascend"].to_i
    )
  rescue JSON::ParserError => e
    raise Error, "BRouter returned malformed JSON: #{e.message}"
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Error, "BRouter unreachable: #{e.message}"
  end
end
