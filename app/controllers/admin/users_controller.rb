module Admin
  class UsersController < AdminController
    def index
      @users = User.all
    end

    def update
      @user = User.find(params[:id])
      if @user.update(user_update_params)
        redirect_to users_path
      else
        redirect_to users_path
      end
    end

    private

    def user_update_params
      params.expect(user: [ :admin ])
    end
  end
end
