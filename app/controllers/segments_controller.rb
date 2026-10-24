class SegmentsController < ApplicationController
  LEADERBOARD_SIZE = 100

  def show
    @segment = Segment.find(params[:id])
    @efforts = @segment.efforts_by(Current.user).to_a
    @leaderboard = @segment.leaderboard.limit(LEADERBOARD_SIZE)
  end
end
