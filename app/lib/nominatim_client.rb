class NominatimClient
  include HTTParty

  base_uri "https://api.maptiler.com"
  headers "User-Agent" => "Velo"

  def reverse_geocode(lat, lon)
    key = Rails.application.credentials.maptiler_api_key

    response = self.class.get(
      "/geocoding/#{lon},#{lat}.json",
      query: { key: key }
    )

    Rails.logger.info "maptiler reverse geocode response: #{response.inspect}"

    # Normalize response to match previous structure usage
    if response.success? && response["features"]&.any?
      place = response["features"].first
      context = place["context"] || []

      parts = context.each_with_object({}) do |c, acc|
        if c["id"].start_with?("place")
          acc["city"] = c["text"]
        elsif c["id"].start_with?("region")
          acc["state"] = c["text"]
        elsif c["id"].start_with?("country")
          acc["country"] = c["text"]
        end
      end

      {
        "reversegeocode" => {
          "addressparts" => parts
        }
      }
    else
      nil
    end
  end
end
