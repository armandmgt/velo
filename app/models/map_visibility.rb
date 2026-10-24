# What of an Activity's map a given viewer may see. The owner sees everything;
# anyone else loses the hidden portion (see CONTEXT.md): the owner's start/end
# trim measured along the track, every point inside one of their address zones,
# or the whole map when the Activity has it hidden.
#
# Every view rendering an Activity's coordinates to a non-owner must go through
# this object, so the hidden coordinates never leave the server.
class MapVisibility
  attr_reader :activity, :viewer

  def initialize(activity, viewer:)
    @activity = activity
    @viewer = viewer
  end

  def owner?
    viewer.present? && viewer.id == activity.user_id
  end

  def map_hidden?
    !owner? && activity.map_hidden?
  end

  def show_map?
    owner? ? activity.path.present? : visible_lines.any?
  end

  # Parallel to the data points in chart order: the point's index is visible
  # when it has a location the viewer may see.
  def visible_indices
    coordinates.each_index.select { |index| coordinates[index] }
  end

  # [lng, lat] per data point in chart order, nil where unknown or hidden.
  def coordinates
    @coordinates ||= data_points.map do |point|
      [ point.location.x, point.location.y ] if point.location && !hidden_ids.include?(point.id)
    end
  end

  # The visible track, cut wherever a hidden point interrupts it.
  def visible_lines
    @visible_lines ||= data_points
      .select(&:location)
      .chunk_while { |a, b| hidden_ids.include?(a.id) == hidden_ids.include?(b.id) }
      .reject { |run| hidden_ids.include?(run.first.id) }
      .map { |run| run.map { [ it.location.x, it.location.y ] } }
      .select { it.size >= 2 }
  end

  def path_geojson
    return activity.path_geojson if owner?
    return if visible_lines.empty?

    geometry =
      if visible_lines.one?
        { type: "LineString", coordinates: visible_lines.first }
      else
        { type: "MultiLineString", coordinates: visible_lines }
      end
    { type: "Feature", properties: {}, geometry: }.to_json
  end

  # [lng, lat] the map opens on before it fits the route. For a non-owner it is
  # a visible point: even the middle of the visible geometry can fall inside an
  # address zone.
  def center
    return visible_lines.first.first unless owner?

    first = activity.path.points.first
    [ first.x, first.y ]
  end

  def chart_data(**)
    data = activity.chart_data(**)
    owner? ? data : data.merge(coordinates:)
  end

  def elevation_chart_data
    data = activity.elevation_chart_data
    owner? || data.nil? ? data : data.merge(coordinates:)
  end

  # Positions, among the located points (the path's vertices), of those the
  # viewer may not see.
  def hidden_vertex_indices
    data_points.select(&:location).each_with_index
      .filter_map { |point, index| index if hidden_ids.include?(point.id) }.to_set
  end

  private

  def data_points
    @data_points ||= activity.activity_data_points.order(:recorded_at, :id).select(:id, :location).to_a
  end

  def hidden_ids
    @hidden_ids ||=
      if owner? then Set.new
      elsif activity.map_hidden? then data_points.map(&:id).to_set
      else Set.new(ActivityDataPoint.connection.select_values(hidden_ids_sql))
      end
  end

  # Distances are summed along the track on the geography type (metres), so
  # the trim follows the route instead of a circle around the start — a circle
  # would let the visible ends triangulate the rider's door.
  def hidden_ids_sql
    ActivityDataPoint.sanitize_sql_array([ <<~SQL, activity_id: activity.id, user_id: activity.user_id, trim: activity.user.map_hide_start_end_distance ])
      WITH located AS (
        SELECT id, recorded_at, location,
               ST_Distance(location, LAG(location) OVER (ORDER BY recorded_at, id)) AS step
        FROM activity_data_points
        WHERE activity_id = :activity_id AND location IS NOT NULL
      ),
      along AS (
        SELECT id, location,
               COALESCE(SUM(step) OVER (ORDER BY recorded_at, id), 0) AS from_start,
               COALESCE(SUM(step) OVER (), 0) AS total
        FROM located
      )
      SELECT id FROM along
      WHERE (:trim > 0 AND (from_start < :trim OR total - from_start < :trim))
         OR EXISTS (
           SELECT 1 FROM map_privacy_zones zone
           WHERE zone.user_id = :user_id AND ST_DWithin(along.location, zone.center, zone.radius)
         )
    SQL
  end
end
