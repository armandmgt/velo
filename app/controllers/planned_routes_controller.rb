class PlannedRoutesController < ApplicationController
  before_action :set_planned_route, only: %i[ show edit update update_visibility destroy ]

  def index
    @planned_routes = Current.user.planned_routes.recent
  end

  def show
    respond_to do |format|
      format.html
      format.gpx do
        send_data @planned_route.to_gpx,
                  filename: "#{@planned_route.name.parameterize.presence || 'route'}.gpx",
                  type: "application/gpx+xml"
      end
    end
  end

  def new
    @planned_route = Current.user.planned_routes.new(sport: params[:sport].presence || "bike")
  end

  def create
    @planned_route = Current.user.planned_routes.new(planned_route_params)
    persist_with_routing(@planned_route, success_flash: t("planned_route.flash.created"), render_on_error: :new)
  end

  def edit
  end

  def update
    @planned_route.assign_attributes(planned_route_params)
    persist_with_routing(@planned_route, success_flash: t("planned_route.flash.updated"), render_on_error: :edit)
  end

  def update_visibility
    @planned_route.update!(visibility: params.require(:planned_route).require(:visibility))
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@planned_route, :share_section),
          partial: "planned_routes/share_section",
          locals: { planned_route: @planned_route }
        )
      end
      format.html { redirect_to @planned_route, status: :see_other }
    end
  end

  def destroy
    @planned_route.destroy!
    redirect_to planned_routes_path, notice: t("planned_route.flash.deleted"), status: :see_other
  end

  # JSON. Body: { sport: "bike", waypoints: [[lon, lat], ...] }
  # Returns: { geojson:, distance_meters:, elevation_gain_meters:, elevation_samples: }
  def preview
    sport, waypoints = parse_preview_body

    unless PlannedRoute.sports.key?(sport) && valid_waypoints?(waypoints)
      return render json: { error: "invalid_input" }, status: :unprocessable_content
    end

    result = RoutePlanner.new(sport: sport, waypoints: waypoints).call

    render json: {
      geojson: {
        type: "Feature",
        geometry: { type: "LineString", coordinates: result.coordinates },
        properties: {}
      },
      waypoints: waypoints,
      coordinates: result.coordinates,
      distance_meters: result.distance_meters,
      elevation_gain_meters: result.elevation_gain_meters,
      elevation_samples: result.elevation_samples
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

  def persist_with_routing(planned_route, success_flash:, render_on_error:)
    if planned_route.invalid?
      flash.now[:alert] = error_sentence(planned_route)
      return render render_on_error, status: :unprocessable_content
    end

    result = RoutePlanner.new(sport: planned_route.sport, waypoints: planned_route.waypoints).call
    planned_route.assign_attributes(
      path: result.path_wkt,
      distance_meters: result.distance_meters,
      elevation_gain_meters: result.elevation_gain_meters,
      elevation_samples: result.elevation_samples,
      routing_profile: result.profile
    )

    if planned_route.save
      redirect_to planned_route, notice: success_flash
    else
      flash.now[:alert] = error_sentence(planned_route)
      render render_on_error, status: :unprocessable_content
    end
  rescue BRouterClient::NoRouteFound
    flash.now[:alert] = t("planned_route.errors.no_route")
    render render_on_error, status: :unprocessable_content
  rescue BRouterClient::Error => e
    Rails.logger.warn("BRouter failed: #{e.message}")
    flash.now[:alert] = t("planned_route.errors.routing_failed")
    render render_on_error, status: :unprocessable_content
  end

  def planned_route_params
    permitted = params.require(:planned_route).permit(:name, :sport, :visibility, :waypoints_json).to_h
    raw = permitted.delete("waypoints_json").to_s
    permitted["waypoints"] = raw.present? ? JSON.parse(raw) : []
    permitted
  rescue JSON::ParserError
    permitted.merge("waypoints" => [])
  end

  MAX_EXTRACTED_WAYPOINTS = 20

  def parse_preview_body
    if params[:gpx_source].present?
      waypoints = GpxExtractor.new(params[:gpx_source].read).parse_points
      retain_every_nth_waypoint = [ 1, waypoints.size / MAX_EXTRACTED_WAYPOINTS ].max
      waypoints = waypoints.filter_map.with_index { |element, i| element if i % retain_every_nth_waypoint == 0 }
      [ params[:sport].to_s, waypoints.pluck(:lon, :lat) ]
    else
      [ params[:sport].to_s, JSON.parse(params[:waypoints]).map { |pair| Array(pair).map(&:to_f) } ]
    end
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
