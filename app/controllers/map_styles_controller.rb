class MapStylesController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    render template: "map_styles/show", layout: false
  end
end
