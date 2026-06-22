class Shared::PlannedRoutesController < ApplicationController
  allow_unauthenticated_access only: :show
  layout "shared"

  rescue_from ActiveSupport::MessageVerifier::InvalidSignature, with: :not_found

  def show
    @planned_route = PlannedRoute.find_signed!(params[:token], purpose: :share)
    return not_found unless @planned_route.shareable_link?

    respond_to do |format|
      format.html
      format.gpx do
        send_data @planned_route.to_gpx,
                  filename: "#{@planned_route.name.parameterize.presence || 'route'}.gpx",
                  type: "application/gpx+xml"
      end
    end
  end

  private

  def not_found
    head :not_found
  end
end
