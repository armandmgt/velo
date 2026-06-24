class PagesController < ApplicationController
  allow_unauthenticated_access
  layout "shared"

  def privacy
  end

  def support
  end
end
