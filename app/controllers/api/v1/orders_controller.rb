# frozen_string_literal: true

class Api::V1::OrdersController < ApplicationController
  # Route: /api/v1/user/orders
  # Method: GET
  # Get all orders of user
  def index
    # Get subscription
    subscription = {}
    chargebee_subscriptions = ChargeBee::Subscription.list({
      "customer_id[is]" => @user.chargebee_customer_id
    })
    chargebee_subscriptions.each { |chargebee_subscription| subscription = chargebee_subscription.subscription }
    orders = MyLib::Transaction.orders(user: @user, subscription: subscription, limit: 100, loopable: true)

    render json: {
      orders: orders
    }, status: :ok
  end
end
