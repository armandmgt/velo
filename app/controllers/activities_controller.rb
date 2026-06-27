class ActivitiesController < ApplicationController
  # Native recorders (#41) upload GPX via `POST /activities` with
  # `Accept: application/json` from outside the webview, so they carry no CSRF
  # token. Auth rides the signed `session_id` cookie (not the CSRF-bearing Rails
  # session), so exempting only the JSON format is safe; the HTML form stays
  # fully protected. Mirrors ConfigurationsController#skip_forgery_protection.
  protect_from_forgery with: :exception, unless: -> { request.format.json? }

  before_action :set_activity, only: %i[ show edit update update_visibility destroy ]

  def index
    @activities = Current.user.activities.order(start_time: :desc)
  end

  def show
  end

  def new
    @activity = Activity.new
  end

  def edit
  end

  def create
    @activity = Current.user.activities.new(activity_params)
    upload = activity_params[:fit_file]

    if upload.respond_to?(:original_filename) && upload.original_filename.to_s.downcase.end_with?(".gpx")
      @activity.parse_gpx_file(upload)
    else
      @activity.parse_fit_file(upload)
    end

    if @activity.save
      respond_to do |format|
        format.html { redirect_to @activity, notice: "Activité créée avec succès." }
        # Native recorders (issue #48) upload GPX out-of-band and navigate the
        # webview to the returned URL — no Turbo redirect to follow.
        format.json { render json: { id: @activity.id, url: activity_url(@activity) }, status: :created, location: @activity }
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = "L'activité n'a pas pu être créée : #{@activity.errors.full_messages.to_sentence}."
          render :new, status: :unprocessable_content
        end
        format.json { render json: { errors: @activity.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def update
    if @activity.update(activity_params.merge(name_pending: false))
      if params[:from] == "name_prompt"
        @pending_activities = Current.user.activities.awaiting_name.order(start_time: :desc)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to @activity, notice: "Activité mise à jour.", status: :see_other }
        end
      else
        redirect_to @activity, notice: "Activité mise à jour.", status: :see_other
      end
    else
      flash.now[:alert] = "L'activité n'a pas pu être mise à jour : #{@activity.errors.full_messages.to_sentence}."
      render :edit, status: :unprocessable_content
    end
  end

  def update_visibility
    @activity.update!(visibility: params.require(:activity).require(:visibility))
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@activity, :share_section),
          partial: "activities/share_section",
          locals: { activity: @activity }
        )
      end
      format.html { redirect_to @activity, status: :see_other }
    end
  end

  def destroy
    @activity.destroy!
    redirect_to activities_path, notice: "Activité supprimée.", status: :see_other
  end

  private

  def set_activity
    @activity = Current.user.activities.find(params[:id])
  end

  def activity_params
    params.expect(activity: [ :name, :description, :sport, :visibility, :fit_file ])
  end
end
