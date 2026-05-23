class IgpsportClient
  include HTTParty

  base_uri "https://prod.en.igpsport.com"
  headers(
    "User-Agent"       => "Velo",
    "Accept"           => "application/json, text/plain, */*",
    "Content-Type"     => "application/json",
    "Qiwu-App-Version" => "8.07.06"
  )

  class Error < StandardError; end
  class AuthenticationError < Error; end

  # Lightweight struct from the activity list — used for cheap pre-dedup.
  RideRef = Data.define(:ride_id, :start_date, :distance)

  # Full struct from the detail endpoint — used for import.
  RideDetail = Data.define(:ride_id, :exercise_type, :start_time, :end_time, :distance, :title, :fit_url)

  # API returns times in the user's local timezone (driven by the TimeZone header).
  # The iGPSport web app is configured to Europe/Paris for this account.
  ACCOUNT_TIME_ZONE = "Europe/Paris"

  EXERCISE_TYPE_TO_SPORT = {
    0 => :bike,         # Outdoor Cycling
    1 => :virtual_ride, # Indoor Cycling
    3 => :run,          # Running
    4 => :trail_run
  }.freeze

  def initialize(connection)
    @connection = connection
  end

  # POST credentials, store the resulting JWT + expiry on the connection.
  # Response: {"code":0, "data":{"access_token":..., "expires_in":604800, ...}}
  def authenticate!
    response = self.class.post(
      "/service/auth/account/login",
      body: { username: connection.email, password: connection.password, appId: "igpsport-web" }.to_json
    )

    raise AuthenticationError, "Login failed (#{response.code}): #{response.body}" unless response.success?

    payload    = response.parsed_response.fetch("data")
    token      = payload.fetch("access_token")
    expires_in = payload.fetch("expires_in")

    connection.update!(
      access_token:     token,
      token_expires_at: Time.current + expires_in.to_i.seconds
    )
  end

  # GET the paginated activity list.
  # Returns {ride_refs: [RideRef, ...], total_pages: n}.
  # GET /service/web-gateway/web-analyze/activity/queryMyActivity
  def activities(page: 1)
    response = self.class.get(
      "/service/web-gateway/web-analyze/activity/queryMyActivity",
      headers: auth_headers,
      query:   { pageNo: page, pageSize: 20, reqType: 0, sort: 1 }
    )

    raise Error, "Activity list failed (#{response.code})" unless response.success?

    data = response.parsed_response.fetch("data")
    refs = data.fetch("rows").map do |row|
      RideRef.new(
        ride_id:    row.fetch("rideId"),
        start_date: Date.strptime(row.fetch("startTime"), "%Y.%m.%d"),
        distance:   row.fetch("rideDistance").to_f
      )
    end

    { ride_refs: refs, total_pages: data.fetch("totalPage") }
  end

  # GET the full detail for a single ride (by integer rideId).
  # Returns a RideDetail including the direct fitUrl.
  # GET /service/web-gateway/web-analyze/activity/queryActivityDetail/{rideId}
  def ride_detail(ride_id)
    response = self.class.get(
      "/service/web-gateway/web-analyze/activity/queryActivityDetail/#{ride_id}",
      headers: auth_headers
    )

    raise Error, "Detail fetch failed for #{ride_id} (#{response.code})" unless response.success?

    d = response.parsed_response.fetch("data")
    RideDetail.new(
      ride_id:       d.fetch("rideId"),
      exercise_type: d.fetch("exerciseType", 0),
      start_time:    parse_local_time(d["startTime"]),
      end_time:      parse_local_time(d["endTime"]),
      distance:      d.fetch("rideDistance").to_f,
      title:         d.fetch("title"),
      fit_url:       d.fetch("fitUrl")
    )
  end

  # GET the raw .fit bytes directly from Aliyun OSS (no auth, different host than base_uri).
  # Uses Net::HTTP instead of the configured HTTParty class to avoid the cross-host safety guard.
  def download_fit(fit_url)
    uri = URI(fit_url)
    http_response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.get(uri.path)
    end
    raise Error, "FIT download failed (#{http_response.code}): #{fit_url}" unless http_response.is_a?(Net::HTTPSuccess)
    http_response.body
  end

  def self.sport_for(exercise_type)
    EXERCISE_TYPE_TO_SPORT.fetch(exercise_type.to_i, :bike)
  end

  private

  attr_reader :connection

  def auth_headers
    { "Authorization" => "Bearer #{connection.access_token}" }
  end

  # API returns times as "2026-05-01 09:51:00" in the account's local timezone.
  def parse_local_time(str)
    return nil if str.blank?
    Time.use_zone(ACCOUNT_TIME_ZONE) { Time.zone.parse(str) }
  end
end
