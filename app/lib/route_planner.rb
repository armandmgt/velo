class RoutePlanner
  Result = Data.define(:path_wkt, :coordinates, :distance_meters, :elevation_gain_meters, :profile)

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
      distance_meters:       route.distance_meters,
      elevation_gain_meters: route.elevation_gain_meters,
      profile:               profile
    )
  end
end
