Rails.application.routes.draw do
  root "dashboard#index"

  get "/status", to: "public/status#index", as: :public_status
  get "/status/:slug", to: "public/status#show", as: :public_status_group

  resources :groups

  resources :hosts do
    member do
      get :probe_chart
      get :probe_results_data
    end
  end

  resources :speed_tests, only: [ :index ] do
    collection do
      get :panel
      post :run
    end
  end

  resource :settings, only: [ :edit, :update ] do
    post :test_notification
  end

  resources :notification_deliveries, only: [ :index ], path: "notifications" do
    member do
      post :retry
    end
  end

  resource :account, only: [ :edit, :update ]
  resource :session
  resources :passwords, param: :token

  # Health check: /up answers when the app boots, /health also checks that probes are running.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show", as: :health
end
