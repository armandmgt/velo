class IgpsportConnectionsController < ApplicationController
  before_action :set_connection

  def edit
  end

  def update
    if @connection.update(filtered_params)
      redirect_to edit_igpsport_connection_path, notice: "Connexion iGPSport enregistrée."
    else
      flash.now[:alert] = "Enregistrement impossible : #{@connection.errors.full_messages.to_sentence}."
      render :edit, status: :unprocessable_content
    end
  end

  def sync
    if @connection.persisted?
      result = IgpsportSyncService.new(@connection).call
      redirect_to edit_igpsport_connection_path, notice: sync_summary(result)
    else
      redirect_to edit_igpsport_connection_path, alert: "Enregistrez d'abord vos identifiants iGPSport."
    end
  end

  def destroy
    @connection.destroy if @connection.persisted?
    redirect_to edit_igpsport_connection_path, notice: "Connexion iGPSport supprimée.", status: :see_other
  end

  private

  def set_connection
    @connection = Current.user.igpsport_connection || Current.user.build_igpsport_connection
  end

  def connection_params
    params.expect(igpsport_connection: [ :email, :password, :enabled ])
  end

  # Don't overwrite a stored password with a blank field on an existing connection.
  def filtered_params
    params = connection_params
    params.delete(:password) if @connection.persisted? && params[:password].blank?
    params
  end

  def sync_summary(result)
    summary = "Synchronisation : #{result[:imported]} importée(s), " \
              "#{result[:skipped]} ignorée(s), #{result[:failed]} échec(s)."
    summary += " #{result[:errors].first[:error]}" if result[:errors].any?
    summary
  end
end
