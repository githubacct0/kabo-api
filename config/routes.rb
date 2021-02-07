# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :admin_users
  devise_for :users
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  post "/login" => "auth#login"

  namespace :api do
    namespace :v1 do
      # Dashboard tab
      get "/user/account" => "users#account"
      # get "/user/next_delivery" => "users#next_delivery"
      # get "/user/meal_plan" => "users#meal_plan"
      # get "/user/delivery_frequency" => "users#delivery_frequency"
      put "/user/delivery_frequency" => "users#update_delivery_frequency"
      post "/user/subscriptions/pause" => "subscriptions#pause"
      post "/user/subscriptions/resume" => "subscriptions#resume"
      post "/user/subscriptions/cancel" => "subscriptions#cancel"

      # Account tab
      get "/user/details" => "users#details"
      post "/user/dogs" => "users#add_dog"
      put "/user/password" => "users#update_password"
      put "/user/delivery_address" => "users#update_delivery_address"

      # Orders tab
      get "/user/orders" => "orders#index"

      # Notifications
      get "/user/notifications" => "notifications#index"

      # Onboarding
      get "/onboarding/signup" => "onboarding#index"
      get "/onboarding/recipes" => "onboarding#recipes"
    end
  end

  namespace :admin do
    post "/login" => "users#login"
    resources :users
  end
end
