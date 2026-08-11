class PlannedRoutesController < ApplicationController
  # Comfortably above a 5-hour 1 Hz ride export (~2.5 MB), and small enough that
  # building a Nokogiri DOM stays cheap inside the request.
  MAX_GPX_BYTES = 5.megabytes
  MAX_SEEDED_WAYPOINTS = 20

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

  # Multipart. Body: gpx_source=<file>
  # Returns: { waypoints: [[lon, lat], ...], name: String|nil }
  #
  # Deliberately does no routing — the client feeds the waypoints back through
  # #preview, so an import stays one cheap call and undo/redo keep working.
  def import_gpx
    upload = params[:gpx_source]
    return render_gpx_error(:gpx_missing) unless upload.respond_to?(:read) && upload.respond_to?(:original_filename)
    return render_gpx_error(:gpx_invalid_type) unless upload.original_filename.to_s.downcase.end_with?(".gpx")
    return render_gpx_error(:gpx_too_large, status: :content_too_large) if upload.size.to_i > MAX_GPX_BYTES

    extractor = GpxExtractor.new(upload.read)
    return render_gpx_error(:gpx_unreadable) unless extractor.gpx?

    points = extractor.parse_points.map { |point| [ point[:lon], point[:lat] ] }
    return render_gpx_error(:gpx_no_points) if points.length < 2

    render json: {
      waypoints: RouteSimplifier.call(points, max_points: MAX_SEEDED_WAYPOINTS),
      name:      extractor.track_name
    }
  rescue Nokogiri::XML::SyntaxError, EncodingError => e
    Rails.logger.info("GPX import rejected: #{e.class}: #{e.message}")
    render_gpx_error(:gpx_unreadable)
  end

  # JSON. Body: { sport: "bike", waypoints: [[lon, lat], ...] }
  # Returns: { geojson:, distance_meters:, elevation_gain_meters:, elevation_samples: }
  def preview
    sport, waypoints = parse_preview_body

    return render json: { error: "invalid_input" }, status: :unprocessable_content unless PlannedRoute.sports.key?(sport)

    if waypoints.length > PlannedRoute::MAX_WAYPOINTS
      return render json: { error: "too_many_waypoints" }, status: :unprocessable_content
    end

    unless valid_waypoints?(waypoints)
      return render json: { error: "invalid_input" }, status: :unprocessable_content
    end

    result = RoutePlanner.new(sport: sport, waypoints: waypoints).call

    render json: {
      geojson: {
        type: "Feature",
        geometry: { type: "LineString", coordinates: result.coordinates },
        properties: {}
      },
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

  # Accepts both encodings this endpoint sees: a JSON body (where Rails has
  # already deserialized params[:waypoints] into an Array) and a form-encoded
  # JSON string. Coordinates are converted strictly — Float(_, exception: false)
  # yields nil for garbage so valid_waypoints? rejects it, where to_f would have
  # silently routed "abc" as 0.0.
  def parse_preview_body
    raw = params[:waypoints]
    raw = JSON.parse(raw) if raw.is_a?(String)

    waypoints = Array(raw).map do |pair|
      pair.is_a?(Array) ? pair.map { |value| Float(value, exception: false) } : pair
    end

    [ params[:sport].to_s, waypoints ]
  rescue JSON::ParserError
    [ params[:sport].to_s, [] ]
  end

  def valid_waypoints?(waypoints)
    waypoints.length >= 2 && waypoints.all? do |pair|
      pair.is_a?(Array) && pair.length == 2 && pair.all?(Numeric) &&
        pair[0].between?(-180, 180) && pair[1].between?(-90, 90)
    end
  end

  def render_gpx_error(code, status: :unprocessable_content)
    render json: { error: code }, status: status
  end

  def error_sentence(record)
    "#{t('planned_route.errors.invalid')} #{record.errors.full_messages.to_sentence}."
  end
end
