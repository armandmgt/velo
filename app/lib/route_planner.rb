class RoutePlanner
  Result = Data.define(
    :path_wkt, :coordinates, :elevation_samples,
    :distance_meters, :elevation_gain_meters, :profile
  )

  EARTH_RADIUS_METERS = 6_371_000.0

  def initialize(sport:, waypoints:, client: BRouterClient.new)
    @sport     = sport.to_sym
    @waypoints = waypoints
    @client    = client
  end

  def call
    profile = PlannedRoute.brouter_profile_for(@sport)
    route   = @client.route(waypoints: @waypoints, profile: profile)

    Result.new(
      path_wkt:              "SRID=4326;LINESTRING(#{route.coordinates.map { |c| "#{c[0]} #{c[1]}" }.join(', ')})",
      coordinates:           route.coordinates,
      elevation_samples:     build_elevation_samples(route.coordinates, route.elevations),
      distance_meters:       route.distance_meters,
      elevation_gain_meters: route.elevation_gain_meters,
      profile:               profile
    )
  end

  private

  # Returns Array<[cumulative_distance_m, elevation_m]> with one entry per
  # coordinate, or nil if BRouter didn't provide z-values.
  def build_elevation_samples(coords, elevations)
    return nil if elevations.nil? || elevations.empty?

    samples = []
    cumulative = 0.0
    coords.each_with_index do |coord, i|
      cumulative += haversine_distance(coords[i - 1], coord) if i.positive?
      samples << [ cumulative.round, elevations[i].round ]
    end
    samples
  end

  def haversine_distance(a, b)
    lon1, lat1 = a
    lon2, lat2 = b
    phi1 = lat1 * Math::PI / 180
    phi2 = lat2 * Math::PI / 180
    dphi    = (lat2 - lat1) * Math::PI / 180
    dlambda = (lon2 - lon1) * Math::PI / 180

    h = Math.sin(dphi / 2)**2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dlambda / 2)**2
    2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(h))
  end
end
