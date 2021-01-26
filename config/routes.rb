Rails.application.routes.draw do
  devise_for :users
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  post "/login" => "auth#login"

  namespace :api do
    namespace :v1 do
      # Dashboard tab
      get "/user/account" => "users#account"

      # Account tab
      get "/user/details" => "users#details"
      post "/user/dogs" => "users#add_dog"
      put "/user/password" => "users#update_password"
      put "/user/delivery_address" => "users#update_delivery_address"

      # Orders tab
      get "/user/orders" => "orders#index"

      # Notifications
      get "/user/notifications" => "notifications#index"
    end
  end
end
