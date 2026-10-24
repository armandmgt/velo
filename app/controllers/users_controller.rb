class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  def show
    @user = Current.user
    @map_privacy_zones = @user.map_privacy_zones.order(:created_at)
  end

  def update
    @user = Current.user
    if @user.update(profile_params)
      redirect_to user_path, notice: "Profil mis à jour."
    else
      flash.now[:alert] = "Enregistrement impossible : #{@user.errors.full_messages.to_sentence}."
      @map_privacy_zones = @user.map_privacy_zones.order(:created_at)
      render :show, status: :unprocessable_content
    end
  end

  def new
    redirect_to after_authentication_url if find_session_by_cookie.present?
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      EmailVerificationsMailer.verify(@user).deliver_later
      redirect_to new_session_path, notice: "Compte créé avec succès. Consultez vos emails pour confirmer votre adresse avant de vous connecter."
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

  def profile_params
    params.expect(user: [ :name, :max_heart_rate, :ftp, :map_hide_start_end_distance ])
  end
end
