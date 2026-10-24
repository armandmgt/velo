class MapPrivacyZonesController < ApplicationController
  before_action :set_zone, only: %i[ edit update destroy ]

  def new
    @zone = Current.user.map_privacy_zones.new
  end

  def create
    @zone = Current.user.map_privacy_zones.new(zone_params)
    if @zone.save
      redirect_to user_path(anchor: "map-visibility"), notice: "Zone masquée ajoutée."
    else
      flash.now[:alert] = "Enregistrement impossible : #{@zone.errors.full_messages.to_sentence}."
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @zone.update(zone_params)
      redirect_to user_path(anchor: "map-visibility"), notice: "Zone masquée mise à jour.", status: :see_other
    else
      flash.now[:alert] = "Enregistrement impossible : #{@zone.errors.full_messages.to_sentence}."
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @zone.destroy!
    redirect_to user_path(anchor: "map-visibility"), notice: "Zone masquée supprimée.", status: :see_other
  end

  private

  def set_zone
    @zone = Current.user.map_privacy_zones.find(params[:id])
  end

  def zone_params
    params.expect(map_privacy_zone: [ :name, :latitude, :longitude, :radius ])
  end
end
