class ConfigurationsController < ApplicationController
  # Native apps fetch their path configuration before the user logs in.
  allow_unauthenticated_access
  skip_forgery_protection

  def ios_v1
    render json: configuration
  end

  def android_v1
    render json: configuration
  end

  private
    # Tells Hotwire Native how to present each URL. A single shared shape for now;
    # the two actions exist so iOS/Android can diverge later without a route change.
    def configuration
      {
        settings: {},
        rules: [
          # Default: every screen pushes onto the native navigation stack.
          {
            patterns: [ "/.*" ],
            properties: { context: "default", pull_to_refresh_enabled: true }
          },
          # Create/edit forms present modally.
          {
            patterns: [ "/new$", "/edit$", "/users/new$", "/session/new$" ],
            properties: { context: "modal", pull_to_refresh_enabled: false }
          }
        ]
      }
    end
end
