require "test_helper"

class RailsEagerLoadingTest < ActiveSupport::TestCase
  test "eager loading" do
    assert_nothing_raised { Rails.application.eager_load! }
  end
end
