class NominatimClient
  include HTTParty

  base_uri "https://api.maptiler.com"
  headers "User-Agent" => "Velo"

  # MapTiler context ids, most specific first. The first one present in the
  # response wins, so a rural point resolves to its town/commune rather than
  # falling all the way back to the region (e.g. "France métropolitaine").
  PLACE_PRIORITY = %w[
    locality municipality place joint_municipality
    county subregion region country
  ].freeze

  # Returns the most specific place name for the coordinates, or nil.
  def reverse_geocode(lat, lon)
    response = self.class.get(
      "/geocoding/#{lon},#{lat}.json",
      query: { key: Rails.application.credentials.maptiler_api_key }
    )

    Rails.logger.info "maptiler reverse geocode response: #{response.inspect}"
    return unless response.success?

    best_place(response["features"]&.first)
  end

  private

  def best_place(feature)
    return unless feature

    by_kind = {}
    Array(feature["context"]).each do |entry|
      kind = entry["id"].to_s.split(".").first
      by_kind[kind] ||= entry["text"]
    end

    PLACE_PRIORITY.each { |kind| return by_kind[kind] if by_kind[kind].present? }

    # Fall back to the feature's own name unless it's just a road segment.
    feature["text"].presence unless Array(feature["place_type"]).include?("road")
  end
end
