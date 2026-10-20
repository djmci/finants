Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :accounts, except: [ :new, :edit, :destroy ] do
    member do
      post :archive
      post :unarchive
    end
  end
  resources :categories, except: [ :new, :edit, :show, :destroy ] do
    member do
      post :archive
      post :unarchive
    end
  end
  resources :transactions, only: [ :index, :create, :update, :destroy ]
  resource :transfer, only: :create
  resource :settings, only: :update
  resource :health, controller: "health", only: :show
  resources :imports, except: [ :edit, :update ] do
    post :commit, on: :member
  end
  resources :recurring_rules, except: [ :new, :edit, :show, :destroy ] do
    member do
      post :archive
      post :unarchive
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "dashboard#index"
end
