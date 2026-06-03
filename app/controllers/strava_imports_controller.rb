class StravaImportsController < ApplicationController
  def new
  end

  def create
    if params[:file].blank?
      redirect_to new_strava_import_path, alert: "Veuillez téléverser un fichier ZIP."
      return
    end

    @result = StravaImportService.new(Current.user, params[:file]).call
    render :result
  end
end
