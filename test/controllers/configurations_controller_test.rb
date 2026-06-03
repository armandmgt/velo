require "test_helper"

class ConfigurationsControllerTest < ActionDispatch::IntegrationTest
  # No login/setup: native apps fetch path configuration before authenticating,
  # so these endpoints must be reachable without a session.

  test "ios_v1 returns path configuration without authentication" do
    get ios_configuration_path

    assert_response :success
    assert_equal "application/json", response.media_type
    body = response.parsed_body
    assert_kind_of Array, body["rules"]
    assert body["rules"].any? { |rule| rule["patterns"].include?("/.*") }
  end

  test "android_v1 returns path configuration without authentication" do
    get android_configuration_path

    assert_response :success
    assert_equal "application/json", response.media_type
    rules = response.parsed_body["rules"]
    assert_kind_of Array, rules
    # Android rules must route to a registered fragment destination via `uri`.
    catch_all = rules.find { |rule| rule["patterns"].include?(".*") }
    assert_equal "hotwire://fragment/web", catch_all.dig("properties", "uri")
  end
end
