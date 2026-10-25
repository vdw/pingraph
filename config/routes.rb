Rails.application.routes.draw do
  root "dashboard#index"

  get "/status", to: "public/status#index", as: :public_status
  get "/status/:slug", to: "public/status#show", as: :public_status_group

  resources :groups

  resources :hosts do
    member do
      get :probe_chart
      get :probe_results_data
      post :regenerate_push_token
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

  resource :account, only: [ :edit, :update ] do
    scope module: :accounts do
      resource :two_factor, only: [ :new, :create, :destroy ]
      resource :recovery_codes, only: [ :create ]
    end
  end
  resources :users, only: [ :index, :new, :create, :destroy ] do
    member do
      post :reset_password
      delete :two_factor, action: :disable_two_factor
    end
  end
  resource :session
  resource :two_factor_challenge, only: [ :new, :create ]
  resources :passwords, param: :token

  # Push monitors (Uptime Kuma's URL format).
  match "/api/push/:token", to: "push#create", via: %i[ get post ], as: :push, format: false

  # Health check: /up answers when the app boots, /health also checks that probes are running.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show", as: :health
end
