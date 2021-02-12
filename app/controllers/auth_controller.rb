# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :require_login, only: [:login]
  def login
    user = User.find_by(email: params[:email])
    if user && user.valid_password?(params[:password])
      payload = { user_id: user.id }
      token = encode_token(payload)

      render json: {
        token: token,
        user: user,
        dogs: user.dogs,
        success: "Welcome back, #{user.first_name}!"
      }, status: 200
    else
      render json: { error: "Invalid Email or Password!" }, status: 500
    end
  end
end
