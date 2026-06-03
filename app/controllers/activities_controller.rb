class ActivitiesController < ApplicationController
  before_action :set_activity, only: %i[ show edit update destroy ]

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
      redirect_to @activity, notice: "Activity was successfully created."
    else
      flash.now[:alert] = "Activity was not created due to the following errors: #{@activity.errors.full_messages.to_sentence}."
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @activity.update(activity_params.merge(name_pending: false))
      @pending_activities = Current.user.activities.awaiting_name.order(start_time: :desc)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @activity, notice: "Activity was successfully updated.", status: :see_other }
      end
    else
      flash.now[:alert] = "Activity was not updated due to the following errors: #{@activity.errors.full_messages.to_sentence}."
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @activity.destroy!
    redirect_to activities_path, notice: "Activity was successfully destroyed.", status: :see_other
  end

  private

  def set_activity
    @activity = Current.user.activities.find(params[:id])
  end

  def activity_params
    params.expect(activity: [ :name, :description, :sport, :fit_file ])
  end
end
