# frozen_string_literal: true

class Admin::UsersController < AdminController
  skip_before_action :require_login, only: [:login]

  PER_PAGE = 10

  def login
    admin = AdminUser.find_by(email: params[:email])
    if admin && admin.valid_password?(params[:password])
      payload = { admin_id: admin.id }
      token = encode_token(payload)

      render json: {
        token: token,
        admin: admin
      }, status: 200
    else
      render json: { error: "Invalid Email or Password!" }, status: 500
    end
  end

  def index
    # Get
    _start = user_list_params[:_start]
    if _start.present?
      users = User.limit(PER_PAGE).offset(_start.to_i)
    else
      users = User.first(PER_PAGE)
    end

    # Order by
    _sort = user_list_params[:_sort]
    if _sort.present?
      _order = user_list_params[:_order]
      case _sort
      when "name"
        users = _order == "ASC" ? users.order(:name) : users.order(name: :desc)
      when "url"
        users = _order == "ASC" ? users.order(:url) : users.order(url: :desc)
      end
    end


    count = users.size
    response.set_header("Access-Control-Expose-Headers", "X-Total-Count")
    response.set_header("X-Total-Count", count)

    render json: users
  end

  private
    def user_list_params
      params.permit(:_sort, :_order, :_start, :_end)
    end
end
