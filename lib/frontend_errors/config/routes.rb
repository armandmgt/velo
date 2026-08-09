# frozen_string_literal: true

FrontendErrors::Engine.routes.draw do
  post "/" => "reports#create", as: :reports
end
