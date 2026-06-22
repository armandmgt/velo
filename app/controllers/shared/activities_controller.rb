class Shared::ActivitiesController < ApplicationController
  allow_unauthenticated_access only: :show
  layout "shared"

  rescue_from ActiveSupport::MessageVerifier::InvalidSignature, with: :not_found

  def show
    @activity = Activity.find_signed!(params[:token], purpose: :share)
    not_found unless @activity.shareable_link?
  end

  private

  def not_found
    head :not_found
  end
end
