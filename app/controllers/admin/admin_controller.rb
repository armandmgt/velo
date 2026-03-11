module Admin
  class AdminController < ApplicationController
    before_action :authorize_admin!

    private

    def authorize_admin!
      redirect_to main_app.root_path unless Current.user.admin?
    end
  end
end
