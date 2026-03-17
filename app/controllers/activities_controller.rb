class ActivitiesController < ApplicationController
  before_action :set_activity, only: %i[ show edit update destroy ]

  def index
    @activities = Current.user.activities
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
    @activity.parse_fit_file(activity_params[:fit_file])

    if @activity.save
      redirect_to @activity, notice: "Activity was successfully created."
    else
      flash.now[:alert] = "Activity was not created due to the following errors: #{@activity.errors.full_messages.to_sentence}."
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @activity.update(activity_params)
      redirect_to @activity, notice: "Activity was successfully updated.", status: :see_other
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
