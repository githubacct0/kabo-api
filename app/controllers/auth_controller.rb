# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :require_login, only: [:login]
  def login
    user = User.find_by(email: params[:email])
    if user && user.authenticate(params[:password])
      payload = { user_id: user.id }
      token = encode_token(payload)
      render json: { user: user, token: token, success: "Welcome back, #{user.email}" }, status: 200
    else
      render json: { error: "Invalid Email or Password!" }, status: 200
    end
  end
end
