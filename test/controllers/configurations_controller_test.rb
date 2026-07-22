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
    assert_cross_tab_rules body["rules"]
    assert_map_settings body["settings"]
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
    assert_cross_tab_rules rules
    assert_map_settings response.parsed_body["settings"]
  end

  private
    # The native recording screen's MapLibre map reads its style URL + accent from
    # `settings.map` at launch (there's no webview to bridge it over).
    def assert_map_settings(settings)
      assert_includes settings["map_style_url"], "api.maptiler.com", "map_style_url must be the MapTiler style"
      assert_match(/\A#[0-9a-fA-F]{6}\z/, settings["map_accent"], "map_accent must be a hex colour")
    end

    # Cross-tab routing rules tag each section with the tab that owns it, and must
    # sit after the catch-all (so `tab` merges onto it) but before the modal rule
    # (so modals still present over the current tab). Both platforms share them.
    def assert_cross_tab_rules(rules)
      tab_names = rules.filter_map { |rule| rule.dig("properties", "tab") }
      assert_equal %w[dashboard activities planned_routes], tab_names

      activities = rules.index { |rule| rule.dig("properties", "tab") == "activities" }
      catch_all = rules.index { |rule| rule["patterns"].include?("/.*") || rule["patterns"].include?(".*") }
      modal = rules.index { |rule| rule["patterns"].include?("/new$") }
      assert catch_all < activities, "tab rules must follow the catch-all"
      assert activities < modal, "tab rules must precede the modal rule"
    end
end
