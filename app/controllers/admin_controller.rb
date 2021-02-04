# frozen_string_literal: true

class AdminController < ActionController::API
  before_action :require_login

  def encode_token(payload)
    JWT.encode(payload, "admin_secret")
  end

  def auth_header
    request.headers["Authorization"]
  end

  def decoded_token
    if auth_header
      token = auth_header.split(" ")[1]
      puts token
      begin
        JWT.decode(token, "admin_secret", true, algorithm: "HS256")
      rescue JWT::DecodeError
        []
      end
    end
  end

  def session_admin
    decoded_hash = decoded_token
    if !decoded_hash.empty?
      admin_id = decoded_hash[0]["admin_id"]
      @admin = AdminUser.find_by(id: admin_id)
    else
      nil
    end
  end

  def logged_in?
    !!session_admin
  end

  def require_login
    render json: { message: "Please Login" }, status: :unauthorized unless logged_in?
  end
end
