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

  namespace :admin, admin: true do
    resources :users
  end

  resource :map_style, only: %i[ show ]

  resources :users, only: %i[ new create ]
  resource :user, only: %i[ show update destroy ]
  resource :session, only: %i[ show new create destroy ]
  resources :passwords, param: :token

  resource :activity_feeds
  resources :activities
  resources :planned_routes, only: %i[ index new create show destroy ] do
    post :preview, on: :collection
  end
  root "activity_feeds#index"

  mount RailsIcons::Engine, at: "/rails_icons" if Rails.env.development?
end
