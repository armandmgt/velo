class ConfigurationsController < ApplicationController
  # Native apps fetch their path configuration before the user logs in.
  allow_unauthenticated_access
  skip_forgery_protection

  # Forms present modally; everything else pushes onto the native nav stack.
  MODAL_PATTERNS = [ "/new$", "/edit$" ].freeze

  # Map configuration for the native recording screen's MapLibre map. The native
  # shells read this from `pathConfiguration.settings` at launch (no webview, so
  # they can't get it over the Strada bridge). `map_style_url` is the same MapTiler
  # streets style the web uses (see map_helpers.js `styleUrl`), so the native
  # basemap matches the web; `map_accent` is the app's `--color-primary` (orange),
  # used for the live route trace + distance hero.
  #
  # Flat string keys (not a nested object): Hotwire Native Android types
  # `settings` as Map<String,String>, so nested objects wouldn't survive there.
  #
  # NOTE: this endpoint is `allow_unauthenticated_access`, so the key here is
  # publicly fetchable. Prefer a dedicated, usage-capped MapTiler key for native.
  def self.map_settings
    key = Rails.application.credentials.maptiler_api_key
    {
      map_style_url: "https://api.maptiler.com/maps/streets/style.json?key=#{key}",
      # The browser-resolved sRGB of the web theme's `--color-primary`
      # (oklch(76% 0.188 70.08)) — so the native trace/accent matches the webviews.
      map_accent: "#f69900"
    }
  end

  # Cross-tab routing. Each bottom tab owns a section of the app, but Hotwire
  # Native pushes a tapped link onto whichever tab's stack it was tapped from —
  # so an activity opened from the dashboard feed would land in the dashboard
  # stack, duplicating what the Activités tab already owns. These rules tag each
  # section with the tab that owns it; the native shells' NavigatorDelegate
  # (iOS) / TabRouteDecisionHandler (Android) key off the `tab` property to
  # switch tabs and route there instead. Declaring the mapping here keeps it a
  # single source of truth shared by both platforms. `tab` names are aligned
  # with the tabs' order in each shell's MainTabs. Only affects `default`
  # context — modals (MODAL_PATTERNS) present over the current tab regardless.
  TAB_RULES = [
    { patterns: [ "^/$" ], properties: { tab: "dashboard" } },
    { patterns: [ "^/activities(/|$)" ], properties: { tab: "activities" } },
    { patterns: [ "^/planned_routes(/|$)" ], properties: { tab: "planned_routes" } }
  ].freeze

  # Full-screen maps: a downward drag pans the map, it must not reload the page.
  MAP_PATTERNS = [ "^/heatmap(\\?|$)" ].freeze

  def ios_v1
    render json: ios_configuration
  end

  def android_v1
    render json: android_configuration
  end

  private
    # Auth pages must override the MODAL_PATTERNS `/new$` match — they're
    # served at the *root* of their dedicated navigator, never as a modal on
    # top of the tab bar. The sign-out marker on /session/new tells the iOS
    # shell to swap back to the unauthenticated root when a tab-bar navigator
    # proposes a visit there.
    AUTH_OVERRIDE = {
      context: "default",
      pull_to_refresh_enabled: false,
      is_after_sign_out_path: true
    }.freeze

    def ios_configuration
      {
        settings: self.class.map_settings,
        rules: [
          { patterns: [ "/.*" ], properties: { context: "default", pull_to_refresh_enabled: true } },
          *TAB_RULES,
          { patterns: MAP_PATTERNS, properties: { pull_to_refresh_enabled: false } },
          { patterns: MODAL_PATTERNS, properties: { context: "modal", pull_to_refresh_enabled: false } },
          { patterns: [ "/session/new$", "/users/new$" ], properties: AUTH_OVERRIDE }
        ]
      }
    end

    # Android rules must route each URL to a registered fragment destination via
    # a `uri`. The catch-all sends everything to the web fragment; matching
    # properties accumulate top-down, so the modal rule only overrides context.
    def android_configuration
      {
        settings: self.class.map_settings,
        rules: [
          {
            patterns: [ ".*" ],
            properties: {
              context: "default",
              uri: "hotwire://fragment/web",
              pull_to_refresh_enabled: true
            }
          },
          *TAB_RULES,
          { patterns: MAP_PATTERNS, properties: { pull_to_refresh_enabled: false } },
          { patterns: MODAL_PATTERNS, properties: { context: "modal", pull_to_refresh_enabled: false } },
          { patterns: [ "/session/new$", "/users/new$" ], properties: AUTH_OVERRIDE }
        ]
      }
    end
end
