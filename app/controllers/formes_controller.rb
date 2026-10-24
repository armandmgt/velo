class FormesController < ApplicationController
  def show
    @forme = Forme.new(Current.user, window: params[:window])
  end
end
