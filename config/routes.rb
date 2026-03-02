Rails.application.routes.draw do
  root "dashboard#index"

  resources :groups

  resources :hosts do
    member do
      get :pings_data
    end
  end

  resource :session
  resources :passwords, param: :token

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
