# frozen_string_literal: true

class Api::V1::OrdersController < ApplicationController
  # Route: /api/v1/user/orders
  # Method: GET
  # Get all orders of user
  def index
    # Get subscription
    subscription = {}
    MyLib::Chargebee.get_subscription_list(
      chargebee_customer_id: @user.chargebee_customer_id
    ).each { |chargebee_subscription| subscription = chargebee_subscription.subscription }
    orders = MyLib::Transaction.orders(user: @user, subscription: subscription, limit: 1, loopable: false)

    render json: {
      orders: orders
    }, status: :ok
  end
end
