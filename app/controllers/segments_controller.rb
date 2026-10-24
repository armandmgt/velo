class SegmentsController < ApplicationController
  before_action :set_activity, only: %i[ new create ]

  LEADERBOARD_SIZE = 100

  def show
    @segment = Segment.find(params[:id])
    @efforts = @segment.efforts_by(Current.user).to_a
    @leaderboard = @segment.leaderboard.limit(LEADERBOARD_SIZE)
  end

  def new
    @segment = Segment.new
  end

  def create
    attrs = params.expect(segment: %i[ name start_index end_index ])
    @segment = Segment.from_activity(@activity, name: attrs[:name],
                                                start_index: attrs[:start_index], end_index: attrs[:end_index])

    if @segment.save
      redirect_to @segment, notice: "Segment créé. Les efforts des activités existantes arrivent dans un instant."
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_activity
    @activity = Current.user.activities.find(params[:activity_id])
  end
end
