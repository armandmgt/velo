class GearComponentsController < ApplicationController
  before_action :set_gear
  before_action :set_component, only: %i[ edit update destroy replace ]

  def new
    @component = @gear.components.new(installed_on: GearComponent.today, kind: "chain")
  end

  def create
    @component = @gear.components.new(component_params)

    if @component.save
      redirect_to @gear, notice: "Composant ajouté."
    else
      flash.now[:alert] = "Le composant n'a pas pu être ajouté : #{@component.errors.full_messages.to_sentence}."
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @component.update(component_params)
      redirect_to @gear, notice: "Composant mis à jour.", status: :see_other
    else
      flash.now[:alert] = "Le composant n'a pas pu être mis à jour : #{@component.errors.full_messages.to_sentence}."
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @component.destroy!
    redirect_to @gear, notice: "Composant supprimé.", status: :see_other
  end

  def replace
    @component.replace!
    redirect_to @gear, notice: "Composant remplacé : le nouveau repart de zéro.", status: :see_other
  end

  private

  def set_gear
    @gear = Current.user.gears.bike.find(params[:gear_id])
  end

  def set_component
    @component = @gear.components.active.find(params[:id])
  end

  def component_params
    params.expect(gear_component: [ :kind, :nickname, :installed_on, :service_interval_km ])
  end
end
