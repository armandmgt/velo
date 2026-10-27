# A named, directional stretch of road or trail shared by every user of the
# instance (see CONTEXT.md). Its vertices are the matcher's corridor; its start
# and end points carry their own GiST indexes so ingestion can narrow ~1,000s of
# segments down to the few an activity passes by before matching precisely.
class Segment < ApplicationRecord
  MIN_DISTANCE = 200
  # Dense enough for the 50 m corridor check, sparse enough to keep a long
  # climb's vertex list small.
  VERTEX_SPACING = 10
  CATEGORIES = %w[cycling running].freeze

  belongs_to :user, optional: true
  has_many :segment_efforts, dependent: :delete_all

  normalizes :name, with: ->(n) { n.strip }

  validates :name, presence: true, length: { maximum: 100 }
  validates :sport_category, inclusion: { in: CATEGORIES }
  validates :distance, numericality: { greater_than_or_equal_to: MIN_DISTANCE,
                                       message: "doit être d'au moins #{MIN_DISTANCE} m" }
  validate :not_a_duplicate, on: :create

  after_create_commit { BackfillSegmentEffortsJob.perform_later(self) }

  # Segments whose start and end both lie within matching tolerance of the
  # given points' line.
  scope :passed_by, ->(points) {
    line = "SRID=4326;LINESTRING(#{points.map { "#{it.lon} #{it.lat}" }.join(', ')})"
    where(<<~SQL, line:, tolerance: SegmentMatcher::START_END_TOLERANCE)
      ST_DWithin(start_point, ST_GeogFromText(:line), :tolerance)
      AND ST_DWithin(end_point, ST_GeogFromText(:line), :tolerance)
    SQL
  }

  # Builds (without saving) the segment covering the owner's located points
  # [start_index..end_index] of an activity.
  def self.from_activity(activity, start_index:, end_index:, name:)
    points = activity.activity_data_points.where.not(location: nil).order(:recorded_at, :id).to_a
    stretch = start_index.to_i < end_index.to_i ? points[start_index.to_i..end_index.to_i] : nil
    segment = new(user: activity.user, name:, sport_category: activity.sport_category.to_s)
    segment.trace(stretch.map { [ it.location.y, it.location.x, it.altitude&.to_f ] }) if stretch&.size.to_i >= 2
    segment.distance ||= 0
    segment
  end

  # Sets the geometry and figures from [lat, lon, altitude] triples.
  def trace(triples)
    self.distance = triples.each_cons(2).sum { |(la1, lo1), (la2, lo2)| Haversine.distance(la1, lo1, la2, lo2) }
    altitudes = triples.filter_map(&:last)
    self.elevation_gain = altitudes.each_cons(2).sum { |a, b| [ b - a, 0 ].max }
    self.average_grade = altitudes.size >= 2 && distance.positive? ? (altitudes.last - altitudes.first) / distance * 100 : 0

    kept = thin(triples)
    self.path = "SRID=4326;LINESTRING(#{kept.map { |lat, lon| "#{lon} #{lat}" }.join(', ')})"
    self.start_point = "SRID=4326;POINT(#{kept.first[1]} #{kept.first[0]})"
    self.end_point = "SRID=4326;POINT(#{kept.last[1]} #{kept.last[0]})"
    self.altitudes = kept.map(&:last).compact.size == kept.size ? kept.map(&:last) : []
  end

  # [lat, lon] per vertex, in riding direction.
  def vertices
    path.points.map { [ it.y, it.x ] }
  end

  def path_geojson
    { type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: path.points.map { [ it.x, it.y ] } } }.to_json
  end

  # Elevation along the segment, by distance from its start.
  def elevation_chart_data
    return if altitudes.empty?

    along = vertices.each_cons(2).reduce([ 0.0 ]) { |acc, (a, b)| acc << acc.last + Haversine.distance(*a, *b) }
    { labels: along.map(&:round), data: altitudes, coordinates: path.points.map { [ it.x, it.y ] } }
  end

  # Each rider's fastest public effort, fastest first.
  def leaderboard
    best = segment_efforts.where(private: false).joins(:activity)
      .select("DISTINCT ON (activities.user_id) segment_efforts.*")
      .order("activities.user_id, segment_efforts.elapsed_seconds, segment_efforts.id")
    SegmentEffort.from(best, :segment_efforts).includes(activity: :user).order(:elapsed_seconds, :id)
  end

  # The rider's efforts, private ones included, fastest first; on a tie the
  # earlier pass wins.
  def efforts_by(user)
    segment_efforts.joins(:activity).where(activities: { user_id: user.id })
      .includes(:activity).order(:elapsed_seconds, "activities.start_time", :start_index)
  end

  private

  def thin(triples)
    kept = [ triples.first ]
    triples[1...-1].each do |triple|
      kept << triple if Haversine.distance(kept.last[0], kept.last[1], triple[0], triple[1]) >= VERTEX_SPACING
    end
    kept << triples.last
  end

  def not_a_duplicate
    return unless start_point && end_point

    tolerance = SegmentMatcher::START_END_TOLERANCE
    twin = Segment.where(sport_category:)
      .where("ST_DWithin(start_point, ST_GeogFromText(?), ?)", start_point.as_text.then { "SRID=4326;#{it}" }, tolerance)
      .where("ST_DWithin(end_point, ST_GeogFromText(?), ?)", end_point.as_text.then { "SRID=4326;#{it}" }, tolerance)
      .first
    errors.add(:base, "Un segment identique existe déjà : « #{twin.name} »") if twin
  end
end
