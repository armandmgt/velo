class NominatimClient
  include HTTParty
  base_uri "http://minipc.armandmgt.fr:8080"
  headers "User-Agent" => "Velo development"

  def search(query)
    self.class.get("/search", query: { q: query })
  end

  def reverse_geocode(lat, lon)
    self.class.get("/reverse", query: { lat: lat, lon: lon })
  end
end
