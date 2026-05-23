class IgpsportSyncService
  def initialize(connection)
    @connection = connection
    @user       = connection.user
    @client     = IgpsportClient.new(connection)
  end

  def call
    result = { imported: 0, skipped: 0, failed: 0, errors: [] }

    client.authenticate! unless connection.token_valid?

    all_ride_refs.each do |ref|
      if already_on_date?(ref)
        result[:skipped] += 1
        next
      end

      detail  = client.ride_detail(ref.ride_id)
      outcome = import_ride(detail)
      result[outcome] += 1 if result.key?(outcome)
    rescue => e
      result[:failed] += 1
      result[:errors] << { ride_id: ref&.ride_id, error: e.message }
    end

    record_status(result, status: "ok")
    result
  rescue => e
    result[:errors] << { ride_id: nil, error: e.message }
    record_status(result, status: "error", error: e.message)
    result
  end

  private

  attr_reader :connection, :user, :client

  def all_ride_refs
    refs = []
    page = 1
    loop do
      page_data = client.activities(page: page)
      refs.concat(page_data[:ride_refs])
      break if page >= page_data[:total_pages]
      page += 1
    end
    refs
  end

  # Quick pre-filter using list data (no detail call, no download):
  # skip if an activity for this user already exists on the same UTC calendar day
  # with a distance within 500 m. Avoids fetching the detail for rides already imported.
  def already_on_date?(ref)
    Activity
      .where(user: user, start_time: ref.start_date.all_day)
      .where("ABS(distance::float - ?) < 500", ref.distance)
      .exists?
  end

  def import_ride(detail)
    Tempfile.create([ "igpsport", ".fit" ]) do |tmp|
      tmp.binmode
      tmp.write(client.download_fit(detail.fit_url))
      tmp.rewind

      activity = user.activities.new(
        name:     detail.title,
        sport:    IgpsportClient.sport_for(detail.exercise_type),
        location: "Unknown"
      )

      File.open(tmp.path, "rb") { |file| activity.parse_fit_file(file, reverse_geocode: false) }

      # Exact dedup by FIT-derived start_time (authoritative, UTC, second-precision).
      return :skipped if Activity.find_by(user: user, start_time: activity.start_time)

      activity.start_time  ||= detail.start_time
      activity.end_time    ||= detail.end_time
      activity.active_time ||= "PT0S"

      return :failed unless activity.save(validate: false)

      :imported
    end
  end

  def record_status(result, status:, error: nil)
    connection.update(
      last_synced_at:   Time.current,
      last_sync_status: status,
      last_sync_error:  error || result[:errors].first&.dig(:error)
    )
  end
end
