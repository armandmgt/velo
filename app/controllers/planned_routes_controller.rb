class PlannedRoutesController < ApplicationController
  before_action :set_planned_route, only: %i[ show destroy ]

  def index
    @planned_routes = Current.user.planned_routes.recent
  end

  def show
  end

  def new
    @planned_route = Current.user.planned_routes.new(sport: params[:sport].presence || "bike")
  end

  def create
    @planned_route = Current.user.planned_routes.new(planned_route_params)

    if @planned_route.invalid?
      flash.now[:alert] = error_sentence(@planned_route)
      return render :new, status: :unprocessable_content
    end

    result = RoutePlanner.new(sport: @planned_route.sport, waypoints: @planned_route.waypoints).call
    @planned_route.assign_attributes(
      path:                  result.path_wkt,
      distance_meters:       result.distance_meters,
      elevation_gain_meters: result.elevation_gain_meters,
      routing_profile:       result.profile
    )

    if @planned_route.save
      redirect_to @planned_route, notice: t("planned_route.flash.created")
    else
      flash.now[:alert] = error_sentence(@planned_route)
      render :new, status: :unprocessable_content
    end
  rescue BRouterClient::NoRouteFound
    flash.now[:alert] = t("planned_route.errors.no_route")
    render :new, status: :unprocessable_content
  rescue BRouterClient::Error => e
    Rails.logger.warn("BRouter failed: #{e.message}")
    flash.now[:alert] = t("planned_route.errors.routing_failed")
    render :new, status: :unprocessable_content
  end

  def destroy
    @planned_route.destroy!
    redirect_to planned_routes_path, notice: t("planned_route.flash.deleted"), status: :see_other
  end

  # JSON. Body: { sport: "bike", waypoints: [[lon, lat], ...] }
  # Returns: { geojson:, distance_meters:, elevation_gain_meters: }
  def preview
    sport, waypoints = parse_preview_body

    unless PlannedRoute.sports.key?(sport) && valid_waypoints?(waypoints)
      return render json: { error: "invalid_input" }, status: :unprocessable_content
    end

    result = RoutePlanner.new(sport: sport, waypoints: waypoints).call

    render json: {
      geojson: {
        type:     "Feature",
        geometry: { type: "LineString", coordinates: result.coordinates },
        properties: {}
      },
      distance_meters:       result.distance_meters,
      elevation_gain_meters: result.elevation_gain_meters
    }
  rescue BRouterClient::NoRouteFound
    render json: { error: "no_route" }, status: :unprocessable_content
  rescue BRouterClient::Error => e
    Rails.logger.warn("BRouter failed: #{e.message}")
    render json: { error: "routing_failed" }, status: :bad_gateway
  end

  private

  def set_planned_route
    @planned_route = Current.user.planned_routes.find(params[:id])
  end

  def planned_route_params
    permitted = params.require(:planned_route).permit(:name, :sport, :waypoints_json).to_h
    raw = permitted.delete("waypoints_json").to_s
    permitted["waypoints"] = raw.present? ? JSON.parse(raw) : []
    permitted
  rescue JSON::ParserError
    permitted.merge("waypoints" => [])
  end

  def parse_preview_body
    [ params[:sport].to_s, Array(params[:waypoints]).map { |pair| Array(pair).map(&:to_f) } ]
  end

  def valid_waypoints?(waypoints)
    waypoints.length >= 2 && waypoints.all? do |pair|
      pair.is_a?(Array) && pair.length == 2 &&
        pair[0].between?(-180, 180) && pair[1].between?(-90, 90)
    end
  end

  def error_sentence(record)
    "#{t('planned_route.errors.invalid')} #{record.errors.full_messages.to_sentence}."
  end
end
