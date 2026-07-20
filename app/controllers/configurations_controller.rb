class ConfigurationsController < ApplicationController
  # Native apps fetch their path configuration before the user logs in.
  allow_unauthenticated_access
  skip_forgery_protection

  # Forms present modally; everything else pushes onto the native nav stack.
  MODAL_PATTERNS = [ "/new$", "/edit$" ].freeze

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
        settings: {},
        rules: [
          { patterns: [ "/.*" ], properties: { context: "default", pull_to_refresh_enabled: true } },
          *TAB_RULES,
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
        settings: {},
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
          { patterns: MODAL_PATTERNS, properties: { context: "modal", pull_to_refresh_enabled: false } },
          { patterns: [ "/session/new$", "/users/new$" ], properties: AUTH_OVERRIDE }
        ]
      }
    end
end
