Rails.application.routes.draw do
  root "dashboard#index"

  resources :groups

  resources :hosts do
    member do
      get :ping_chart
      get :pings_data
    end
  end

  resources :speed_tests, only: [ :index ] do
    collection do
      get :panel
      post :run
    end
  end

  resource :settings, only: [ :edit, :update ]

  resource :session
  resources :passwords, param: :token

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
