Rails.application.routes.draw do
  devise_for :users
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  post "/login" => "auth#login"

  namespace :api do
    namespace :v1 do
      get "/user" => "users#details"
      post "/user/dogs" => "users#add_dog"
    end
  end
end
