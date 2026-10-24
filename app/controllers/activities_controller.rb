class ActivitiesController < ApplicationController
  # A JSON create comes from outside the webview and carries no CSRF token; auth
  # rides the signed `session_id` cookie instead. Nothing calls it today — kept
  # for the offline upload queue.
  protect_from_forgery with: :exception, unless: -> { request.format.json? }

  before_action :set_activity, only: %i[ show edit update update_visibility destroy ]

  # Douglas-Peucker tolerance (degrees, ~33 m) for the list thumbnails. The cards
  # only draw a 60-point SVG polyline, so the full ~4k-point track is wasted
  # transfer + RGeo allocation. Simplifying in SQL cuts the index payload ~40×.
  THUMBNAIL_SIMPLIFY_TOLERANCE = 0.0003

  def index
    # Select every column except the heavy `path`, then re-add a simplified
    # `path` under the same name so `route_thumbnail` casts it to RGeo as usual.
    columns = Activity.column_names - [ "path" ]
    @activities = Current.user.activities
      .select(*columns, Arel.sql("ST_Simplify(path, #{THUMBNAIL_SIMPLIFY_TOLERANCE}) AS path"))
      .order(start_time: :desc)
  end

  def show
  end

  def new
    @activity = Activity.new
  end

  def edit
  end

  def create
    # The shell learns of success only once the review page reports back, so a
    # process killed in between would otherwise upload the ride twice.
    if (replay = replayed_recording)
      return respond_with_created(replay)
    end

    attrs = activity_params
    @activity = Current.user.activities.new(attrs)
    upload = attrs[:source_file]

    # No time fallbacks: a rider's upload of a timeless file must still fail
    # validation as a 422 rather than be silently stamped with the current time.
    ActivityIngestion.call(@activity, upload, filename: upload.try(:original_filename),
                                              gear_chosen: attrs.key?(:gear_id))

    if @activity.save
      respond_with_created(@activity)
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = "L'activité n'a pas pu être créée : #{@activity.errors.full_messages.to_sentence}."
          render :new, status: :unprocessable_content
        end
        format.json { render json: { errors: @activity.errors.full_messages }, status: :unprocessable_content }
      end
    end
  rescue ActiveRecord::RecordNotUnique
    (replay = replayed_recording) ? respond_with_created(replay) : raise
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

  def replayed_recording
    uuid = activity_params[:recording_uuid].presence
    uuid && Current.user.activities.find_by(recording_uuid: uuid)
  end

  def respond_with_created(activity)
    respond_to do |format|
      format.html { redirect_to activity, notice: "Activité créée avec succès." }
      format.json { render json: { id: activity.id, url: activity_url(activity) }, status: :created, location: activity }
    end
  end

  def set_activity
    @activity = Current.user.activities.find(params[:id])
  end

  # `activity[fit_file]` stays accepted as an alias for `activity[source_file]`:
  # builds predating ADR 0003 still carry the deleted native uploader and POST
  # the old name. See ADR 0005. `source_file` wins when both are sent.
  def activity_params
    permitted = params.expect(activity: [ :name, :description, :sport, :visibility,
                                          :source_file, :fit_file, :recording_uuid, :gear_id ])
    alias_upload = permitted.delete(:fit_file)
    permitted[:source_file] ||= alias_upload if alias_upload

    # A form always sends the key, so an unnamed upload arrives as "" — which
    # would defeat the `name ||=` fallback to the file's own track name.
    permitted[:name] = nil if permitted.key?(:name) && permitted[:name].blank?
    permitted
  end
end
