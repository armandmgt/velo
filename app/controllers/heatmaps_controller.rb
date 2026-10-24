class HeatmapsController < ApplicationController
  MVT_CONTENT_TYPE = "application/vnd.mapbox-vector-tile".freeze

  before_action :require_user
  before_action :set_heatmap

  def show
    @bounds = @heatmap.bounds
    @activity_count = @heatmap.activities.count
    @years = Current.user.activities.where.not(path: nil)
      .distinct.pluck(Arel.sql("EXTRACT(YEAR FROM start_time)::int")).sort.reverse
  end

  def tile
    z, x, y = params.values_at(:z, :x, :y).map(&:to_i)
    return head :bad_request unless Heatmap.valid_tile?(z, x, y)

    key = [ @heatmap.cache_key, z, x, y ].join("/")
    if stale?(etag: key)
      data = Rails.cache.fetch(key) { @heatmap.tile(z, x, y) }
      send_data data, type: MVT_CONTENT_TYPE, disposition: :inline
    end
  end

  private
    def require_user
      head :forbidden unless Current.user
    end

    def set_heatmap
      @heatmap = Heatmap.from_params(Current.user, params)
    end
end
