class ConfigurationsController < ApplicationController
  # Native apps fetch their path configuration before the user logs in.
  allow_unauthenticated_access
  skip_forgery_protection

  # Forms present modally; everything else pushes onto the native nav stack.
  MODAL_PATTERNS = [ "/new$", "/edit$" ].freeze

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
          { patterns: MODAL_PATTERNS, properties: { context: "modal", pull_to_refresh_enabled: false } },
          { patterns: [ "/session/new$", "/users/new$" ], properties: AUTH_OVERRIDE }
        ]
      }
    end
end
