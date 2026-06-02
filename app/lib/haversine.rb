# Great-circle distance between two lat/lon points, in meters.
module Haversine
  EARTH_RADIUS_M = 6_371_000.0

  module_function

  def distance(lat1, lon1, lat2, lon2)
    rlat1 = lat1 * Math::PI / 180
    rlat2 = lat2 * Math::PI / 180
    dlat = (lat2 - lat1) * Math::PI / 180
    dlon = (lon2 - lon1) * Math::PI / 180

    a = Math.sin(dlat / 2)**2 +
        Math.cos(rlat1) * Math.cos(rlat2) * Math.sin(dlon / 2)**2
    EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end
end
