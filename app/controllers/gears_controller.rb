class GearsController < ApplicationController
  before_action :set_gear, only: %i[ show edit update destroy retire reactivate ]

  def index
    gears = Current.user.gears.includes(:gear_defaults, photo_attachment: :blob).order(:name)
    @active_gears, @retired_gears = gears.partition { |gear| !gear.retired? }
  end

  def show
    @totals = @gear.totals
    @components = @gear.components.active.with_distance.order(:installed_on)
    @retired_components = @gear.components.retired.order(retired_at: :desc)
  end

  def new
    @gear = Current.user.gears.new(kind: params[:kind].presence_in(Gear.kinds.keys) || "bike")
  end

  def create
    @gear = Current.user.gears.new(gear_params.merge(params.expect(gear: [ :kind ])))

    if @gear.save
      redirect_to @gear, notice: "Matériel ajouté."
    else
      flash.now[:alert] = "Le matériel n'a pas pu être ajouté : #{@gear.errors.full_messages.to_sentence}."
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @gear.update(gear_params)
      redirect_to @gear, notice: "Matériel mis à jour.", status: :see_other
    else
      flash.now[:alert] = "Le matériel n'a pas pu être mis à jour : #{@gear.errors.full_messages.to_sentence}."
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @gear.destroy!
    redirect_to gears_path, notice: "Matériel supprimé. Ses activités sont conservées.", status: :see_other
  end

  def retire
    @gear.retire!
    redirect_to @gear, notice: "Matériel retiré.", status: :see_other
  end

  def reactivate
    @gear.reactivate!
    redirect_to @gear, notice: "Matériel remis en service.", status: :see_other
  end

  private

  def set_gear
    @gear = Current.user.gears.find(params[:id])
  end

  # The default-sports checkboxes always send the key (with a blank hidden
  # entry), so unticking every sport clears the defaults.
  def gear_params
    params.expect(gear: [ :name, :brand, :model, :photo, default_sports: [] ])
  end
end
