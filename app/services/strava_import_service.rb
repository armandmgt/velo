require "zip"

class StravaImportService
  def initialize(user, uploaded_file)
    @user = user
    @uploaded_file = uploaded_file
  end

  def call
    result = { imported: 0, skipped: 0, failed: 0, errors: [] }

    Zip::File.open(uploaded_file.path) do |zip|
      zip.each do |entry|
        next if entry.directory?

        name = entry.name.downcase
        next unless name.end_with?(".fit") || name.end_with?(".fit.gz")

        begin
          outcome = import_entry(entry, gzipped: name.end_with?(".fit.gz"))
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

  def import_entry(entry, gzipped:)
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
      import_fit(tmp.path)
    end
  end

  def import_fit(file_path)
    activity = user.activities.new(
      name: "Imported activity",
      sport: :bike, # default
      location: "Unknown" # ensure validation passes without geocoding
    )

    File.open(file_path, "rb") do |file|
      activity.parse_fit_file(file, reverse_geocode: false)
    end

    return :skipped if duplicate?(activity)

    # Ensure DB-required fields are present
    activity.start_time ||= Time.current
    activity.end_time ||= activity.start_time
    activity.active_time ||= "PT0S"

    # Persist even if some optional fields are missing
    return :failed unless activity.save(validate: false)

    :imported
  end

  def duplicate?(activity)
    Activity.exists?(
      user: user,
      start_time: activity.start_time,
      end_time: activity.end_time,
      distance: activity.distance
    )
  end
end
