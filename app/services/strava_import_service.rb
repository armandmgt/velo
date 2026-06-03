require "zip"
require "csv"

class StravaImportService
  SPORT_MAP = {
    "Ride"               => :bike,
    "MountainBikeRide"   => :mountain_bike_ride, "Mountain Bike Ride" => :mountain_bike_ride,
    "GravelRide"         => :gravel_ride,         "Gravel Ride"        => :gravel_ride,
    "VirtualRide"        => :virtual_ride,        "Virtual Ride"       => :virtual_ride,
    "EBikeRide"          => :e_bike_ride,         "E-Bike Ride"        => :e_bike_ride,
    "Run"                => :run,
    "TrailRun"           => :trail_run,           "Trail Run"          => :trail_run,
    "VirtualRun"         => :virtual_run,         "Virtual Run"        => :virtual_run,
    "Walk"               => :walk,
    "Hike"               => :hike,
    "AlpineSki"          => :alpine_ski,          "Alpine Ski"         => :alpine_ski,
    "NordicSki"          => :nordic_ski,          "Nordic Ski"         => :nordic_ski,
    "Swim"               => :swim,
    "Workout"            => :workout
  }.freeze

  def initialize(user, uploaded_file)
    @user = user
    @uploaded_file = uploaded_file
  end

  def call
    result = { imported: 0, skipped: 0, failed: 0, errors: [] }

    Zip::File.open(uploaded_file.path) do |zip|
      csv_index = build_csv_index(zip)

      zip.each do |entry|
        next if entry.directory?

        name = entry.name.downcase
        format = activity_format(name)
        next unless format

        begin
          metadata = csv_index[entry.name] || {}
          outcome = import_entry(entry, format: format, gzipped: name.end_with?(".gz"), metadata: metadata)
          result[outcome] += 1 if result.key?(outcome)
        rescue => e
          result[:failed] += 1
          result[:errors] << { file: entry.name, error: e.message }
        end
      end
    end

    result
  end

  private

  attr_reader :user, :uploaded_file

  def build_csv_index(zip)
    csv_entry = zip.find_entry("activities.csv")
    return {} unless csv_entry

    content = csv_entry.get_input_stream.read.force_encoding("UTF-8")
    CSV.parse(content, headers: true).each_with_object({}) do |row, index|
      filename = row["Filename"]
      next if filename.blank?

      index[filename] = {
        name: row["Activity Name"].presence || "Sortie importée",
        name_pending: row["Activity Name"].blank?,
        sport: SPORT_MAP[row["Activity Type"]] || :bike
      }
    end
  end

  def activity_format(name)
    return :fit if name.end_with?(".fit") || name.end_with?(".fit.gz")
    return :gpx if name.end_with?(".gpx") || name.end_with?(".gpx.gz")

    nil
  end

  def import_entry(entry, format:, gzipped:, metadata:)
    Tempfile.create([ "activity", ".#{format}" ]) do |tmp|
      entry.get_input_stream do |io|
        if gzipped
          require "zlib"
          Zlib::GzipReader.wrap(io) { |gz| IO.copy_stream(gz, tmp) }
        else
          IO.copy_stream(io, tmp)
        end
      end

      tmp.rewind
      import_file(tmp.path, format: format, metadata: metadata, filename: source_filename(entry, format))
    end
  end

  # Decompressed, format-appropriate name for the retained source attachment.
  def source_filename(entry, format)
    base = File.basename(entry.name).sub(/\.gz\z/i, "")
    base.downcase.end_with?(".#{format}") ? base : "#{base}.#{format}"
  end

  def import_file(file_path, format:, metadata:, filename:)
    activity = user.activities.new(
      name: metadata[:name] || "Sortie importée",
      name_pending: metadata.fetch(:name_pending, true),
      sport: metadata[:sport] || :bike,
      location: "Unknown"
    )

    File.open(file_path, "rb") do |file|
      if format == :gpx
        activity.parse_gpx_file(file, reverse_geocode: false)
      else
        activity.parse_fit_file(file, reverse_geocode: false)
      end
    end

    existing = find_duplicate(activity)
    if existing
      existing.update(name: activity.name, sport: activity.sport)
      return :skipped
    end

    # Ensure DB-required fields are present
    activity.start_time ||= Time.current
    activity.end_time ||= activity.start_time
    activity.active_time ||= "PT0S"

    # Persist even if some optional fields are missing
    return :failed unless activity.save(validate: false)

    # Retain the source so the activity can be re-imported later.
    File.open(file_path, "rb") do |file|
      activity.fit_file.attach(io: file, filename: filename)
    end

    :imported
  end

  def find_duplicate(activity)
    Activity.find_by(
      user: user,
      start_time: activity.start_time,
      end_time: activity.end_time,
      distance: activity.distance
    )
  end
end
