require "zip"
require "csv"

class StravaImportService
  SPORT_MAP = {
    "Run" => :run,
    "VirtualRun" => :run,
    "TrailRun" => :run,
    "Walk" => :run
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
        next unless name.end_with?(".fit") || name.end_with?(".fit.gz")

        begin
          metadata = csv_index[entry.name] || {}
          outcome = import_entry(entry, gzipped: name.end_with?(".fit.gz"), metadata: metadata)
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
        name: row["Activity Name"].presence || "Imported activity",
        sport: SPORT_MAP[row["Activity Type"]] || :bike
      }
    end
  end

  def import_entry(entry, gzipped:, metadata:)
    Tempfile.create([ "activity", ".fit" ]) do |tmp|
      entry.get_input_stream do |io|
        if gzipped
          require "zlib"
          Zlib::GzipReader.wrap(io) { |gz| IO.copy_stream(gz, tmp) }
        else
          IO.copy_stream(io, tmp)
        end
      end

      tmp.rewind
      import_fit(tmp.path, metadata: metadata)
    end
  end

  def import_fit(file_path, metadata:)
    activity = user.activities.new(
      name: metadata[:name] || "Imported activity",
      sport: metadata[:sport] || :bike,
      location: "Unknown"
    )

    File.open(file_path, "rb") do |file|
      activity.parse_fit_file(file, reverse_geocode: false)
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
