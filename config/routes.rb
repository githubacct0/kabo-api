# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :admin_users
  devise_for :users
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  post "/login" => "auth#login"

  namespace :api do
    namespace :v1 do
      # Dashboard tab
      put "/user/delivery_frequency" => "users#update_delivery_frequency"
      post "/user/apply_coupon" => "users#apply_coupon"
      get "/user/subscriptions" => "subscriptions#index"
      post "/user/subscriptions/pause" => "subscriptions#pause"
      post "/user/subscriptions/resume" => "subscriptions#resume"
      post "/user/subscriptions/cancel" => "subscriptions#cancel"
      get "/user/subscriptions/meal_plans" => "subscriptions#meal_plans"
      post "/user/subscriptions/portions" => "subscriptions#daily_portions"
      post "/user/subscriptions/meal_plan/estimate" => "subscriptions#estimate_meal_plan"
      put "/user/subscriptions/meal_plan" => "subscriptions#update_meal_plan"

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
      get "/onboarding/portions" => "onboarding#portions"
      post "/onboarding/users" => "onboarding#create"
      put "/onboarding/users/:user_id" => "onboarding#update"

      # Checkout
      post "/checkout/:checkout_token/estimate" => "checkout#estimate"
      post "/checkout/postal_code/validate" => "checkout#validate_postal_code"
    end
  end

  namespace :admin do
    post "/login" => "users#login"
    resources :users
  end
end
