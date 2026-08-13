module Admin
  class AdminController < ApplicationController
    # Bearer-token auth is scoped to the admin namespace: this is the only surface a service
    # account is meant to reach (the Solid Errors dashboard hangs off this controller via
    # config.solid_errors.base_controller_class). Everywhere else, a session still means a
    # person with a cookie. Included after Authentication, which ApplicationController brings.
    include ServiceAccountAuthentication

    before_action :authorize_admin!

    private

    # Safe navigation on `user` matters now that a session can be a service account, which
    # has nobody behind it: those are trusted API clients, so they pass without a user.
    def authorize_admin!
      redirect_to main_app.root_path unless Current.user&.admin? || Current.session&.service_account?
    end
  end
end
