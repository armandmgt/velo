require "test_helper"

class FitExtractorTest < ActiveSupport::TestCase
  setup do
    @activity = Activity.new(sport: :bike)
    @extractor = FitExtractor.new(@activity, reverse_geocode: false)
  end

  test "on_record extracts altitude when present" do
    @extractor.on_record({ "timestamp" => 1_000_000, "altitude" => 234.6 })
    dp = @extractor.instance_variable_get(:@data_points).values.first
    assert_in_delta 234.6, dp.altitude.to_f
  end

  test "on_record prefers enhanced_altitude over altitude" do
    @extractor.on_record({
      "timestamp" => 1_000_000,
      "altitude" => 234.6,
      "enhanced_altitude" => 234.8
    })
    dp = @extractor.instance_variable_get(:@data_points).values.first
    assert_in_delta 234.8, dp.altitude.to_f
  end

  test "on_record leaves altitude nil when neither key is present" do
    @extractor.on_record({ "timestamp" => 1_000_000, "speed" => 10.0 })
    dp = @extractor.instance_variable_get(:@data_points).values.first
    assert_nil dp.altitude
  end
end
