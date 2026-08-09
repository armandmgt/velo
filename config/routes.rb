Rails.application.routes.draw do
  resources :strava_imports, only: %i[new create]

  resource :igpsport_connection, only: %i[edit update destroy] do
    post :sync
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Hotwire Native path configuration (fetched by the native apps on launch, pre-login).
  get "configurations/ios_v1"     => "configurations#ios_v1",     as: :ios_configuration
  get "configurations/android_v1" => "configurations#android_v1", as: :android_configuration

  # Browser errors are posted here and reported through Rails.error, so they land
  # wherever server-side errors do.
  mount FrontendErrors::Engine, at: "/frontend_errors"

  namespace :admin, admin: true do
    resources :users

    # solid_errors is a production-only gem, so the constant doesn't exist in
    # dev/test. Access is gated by `config.solid_errors.base_controller_class`
    # (Admin::AdminController), not by this namespace — a mounted engine doesn't
    # inherit the surrounding scope's filters.
    mount SolidErrors::Engine, at: "solid_errors" if defined?(SolidErrors::Engine)
  end

  resource :map_style, only: %i[ show ]

  resources :users, only: %i[ new create ]
  resource :user, only: %i[ show update destroy ]
  resource :session, only: %i[ show new create destroy ]
  resource :email_verification, only: %i[ show create ]
  resources :passwords, param: :token

  resource :activity_feeds
  resources :activities do
    patch :visibility, on: :member, action: :update_visibility
  end
  resources :planned_routes, only: %i[ index new create edit update show destroy ] do
    post :preview, on: :collection
    patch :visibility, on: :member, action: :update_visibility
  end

  get "/a/:token", to: "shared/activities#show", as: :shared_activity
  get "/r/:token(.:format)", to: "shared/planned_routes#show",
      as: :shared_planned_route, constraints: { format: /(html|gpx)/ }

  get "privacy", to: "pages#privacy", as: :privacy
  get "support", to: "pages#support", as: :support

  root "activity_feeds#index"

  mount RailsIcons::Engine, at: "/rails_icons" if Rails.env.development?
end
