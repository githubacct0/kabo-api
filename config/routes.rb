Rails.application.routes.draw do
  devise_for :users
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  post "/login" => "auth#login"

  namespace :api do
    namespace :v1 do
      # Account tab
      get "/user/account" => "users#account"
      post "/user/dogs" => "users#add_dog"

      # Orders tab
      get "/user/orders" => "users#orders"

      # Notifications
      get "/user/notifications" => "users#notifications"
    end
  end
end
