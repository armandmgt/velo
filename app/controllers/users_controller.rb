class UsersController < ApplicationController
  before_action :set_user, only: %i[ show edit update destroy ]

  def index
    @users = User.all
  end

  def show
  end

  def new
    @user = User.new
  end

  def edit
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to @user, notice: "User was successfully created."
    else
      flash.now[:alert] = "User was not created due to the following errors: #{@user.errors.full_messages.to_sentence}."
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: "User was successfully updated.", status: :see_other
    else
      flash.now[:alert] = "User was not updated due to the following errors: #{@user.errors.full_messages.to_sentence}."
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @user.destroy!
    redirect_to users_path, notice: "User was successfully destroyed.", status: :see_other
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.fetch(:user, {})
  end
end
