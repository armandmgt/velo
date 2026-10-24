require "test_helper"

class BestEfforts::RemovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @effort = activities(:two).best_efforts.create!(distance: "5k", elapsed_seconds: 1_500,
                                                    start_index: 0, end_index: 1, rank: 1)
  end

  test "the owner removes and restores an effort" do
    login(users(:two))

    post best_effort_removal_url(@effort)
    assert_redirected_to activity_url(activities(:two))
    assert @effort.reload.removed?

    delete best_effort_removal_url(@effort)
    assert_not @effort.reload.removed?
  end

  test "nobody else can touch it" do
    login(users(:one))

    post best_effort_removal_url(@effort)

    assert_response :not_found
    assert_not @effort.reload.removed?
  end
end
