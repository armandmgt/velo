# A rider's own activity paths, filtered by sport category and date range, and
# served as Mapbox vector tiles. Owner-only: every query is rooted at
# `user.activities`, so a tile can never carry another user's path, and the full
# track is drawn — hidden portions only hide a map from other people.
class Heatmap
  SPORT_CATEGORIES = %w[cycling running other].freeze
  CUSTOM_PERIOD = "custom".freeze

  LAYER = "paths".freeze
  EXTENT = 4096
  BUFFER = 64
  MAX_ZOOM = 14
  # MapLibre draws a vector tile 512 CSS px wide; simplifying to one of those
  # pixels keeps low-zoom tiles small without visible loss.
  DISPLAY_TILE_SIZE = 512
  WEB_MERCATOR_WORLD_METERS = 40_075_016.685_578_49

  attr_reader :user, :sport_category, :period, :from, :to

  def self.from_params(user, params)
    sport_category = params[:sport].presence_in(SPORT_CATEGORIES)
    period = params[:period].to_s

    if period.match?(/\A\d{4}\z/)
      year = period.to_i
      new(user, sport_category:, period:, from: Date.new(year, 1, 1), to: Date.new(year, 12, 31))
    elsif period == CUSTOM_PERIOD
      new(user, sport_category:, period:, from: parse_date(params[:from]), to: parse_date(params[:to]))
    else
      new(user, sport_category:)
    end
  end

  def self.parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def self.valid_tile?(z, x, y)
    z.between?(0, MAX_ZOOM) && [ x, y ].all? { |n| n.between?(0, 2**z - 1) }
  end

  def initialize(user, sport_category: nil, period: nil, from: nil, to: nil)
    @user = user
    @sport_category = sport_category
    @period = period
    @from = from
    @to = to
  end

  def activities
    scope = user.activities.where.not(path: nil)
    scope = scope.where(sport: sports) if sport_category
    scope = scope.where(start_time: from.beginning_of_day..) if from
    scope = scope.where(start_time: ...to.next_day.beginning_of_day) if to
    scope
  end

  def filter_params
    { sport: sport_category, period:, from: (from if custom_period?), to: (to if custom_period?) }.compact
  end

  def custom_period?
    period == CUSTOM_PERIOD
  end

  # [[west, south], [east, north]], or nil when no activity matches.
  def bounds
    west, south, east, north = activities.pick(
      Arel.sql("ST_XMin(ST_Extent(path))"), Arel.sql("ST_YMin(ST_Extent(path))"),
      Arel.sql("ST_XMax(ST_Extent(path))"), Arel.sql("ST_YMax(ST_Extent(path))")
    )
    [ [ west, south ], [ east, north ] ] if west
  end

  # Changes whenever the rider adds, edits or deletes an activity: a deletion
  # lowers the count, anything else moves the latest `updated_at`.
  def cache_key
    count, last_updated_at = user.activities.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
    [ "heatmap", user.id, count, last_updated_at&.to_fs(:usec), *filter_params.values_at(:sport, :period, :from, :to) ]
      .map(&:to_s).join("/")
  end

  def tile(z, x, y)
    tolerance = WEB_MERCATOR_WORLD_METERS / 2**z / DISPLAY_TILE_SIZE
    margin = BUFFER.to_f / EXTENT
    # Older activities stored their path without an SRID; every path is lon/lat.
    features = activities
      .where("activities.path && ST_Transform(ST_TileEnvelope(?, ?, ?, margin => ?), 4326)", z, x, y, margin)
      .select(ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, tolerance, z, x, y, EXTENT, BUFFER ]))
        ST_AsMVTGeom(
          ST_Simplify(ST_Transform(ST_SetSRID(activities.path, 4326), 3857), ?),
          ST_TileEnvelope(?, ?, ?), ?, ?, true
        ) AS geom
      SQL

    sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, LAYER, EXTENT ])
      SELECT ST_AsMVT(features, ?, ?, 'geom') FROM (#{features.to_sql}) AS features WHERE geom IS NOT NULL
    SQL
    ActiveRecord::Base.connection.select_all(sql).cast_values.first.to_s
  end

  private
    def sports
      Activity::SPORT_CATEGORY.filter_map { |sport, category| sport.to_s if category.to_s == sport_category }
    end
end
