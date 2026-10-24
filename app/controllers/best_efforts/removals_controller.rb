class BestEfforts::RemovalsController < ApplicationController
  before_action :set_best_effort

  def create
    @best_effort.remove!
    redirect_back_or_to activity_path(@best_effort.activity_id), status: :see_other
  end

  def destroy
    @best_effort.restore!
    redirect_back_or_to activity_path(@best_effort.activity_id), status: :see_other
  end

  private

  def set_best_effort
    @best_effort = BestEffort.joins(:activity).where(activities: { user_id: Current.user.id })
      .find(params[:best_effort_id])
  end
end
