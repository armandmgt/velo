class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  def show
  end

  def new
    redirect_to after_authentication_url if find_session_by_cookie.present?
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to new_session_path, notice: "Compte créé avec succès. Il doit être approuvé par un admin avant de pouvoir vous connecter."
    else
      redirect_to new_user_path, alert: user.errors.full_messages.join(", ")
    end
  end

  def destroy
    Current.user.destroy!
    redirect_to new_session_path
  end

  private

  def user_params
    params.expect(user: [ :email_address, :password ])
  end
end
