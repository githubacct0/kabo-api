# frozen_string_literal: true

class Api::V1::UsersController < ApplicationController
  # Route: /api/v1/user/account
  # Method: GET
  # Get user's account_details, billing, delivery_address, last 2 order
  def account
    subscriptions = {}
    subscription = {}
    active_subscription = {}
    subscription_phase = {}
    shipping_address = {}
    billing_address = {}
    card = {}
    payment_method = {}
    payment_source = {}

    chargebee_subscriptions = ChargeBee::Subscription.list({
      "customer_id[is]" => @user.chargebee_customer_id
    })
    chargebee_subscriptions.each do |chargebee_subscription|
      subscriptions[chargebee_subscription.subscription.id] = {
        status: chargebee_subscription.subscription.status
      }
      subscription = chargebee_subscription.subscription
      active_subscription = subscription if ["active", "future"].include? subscription.status
      customer = chargebee_subscription.customer
      card = chargebee_subscription.card
      shipping_address = subscription.shipping_address
      billing_address = customer.billing_address
      payment_method = customer.payment_method

      if payment_method.type == "paypal_express_checkout"
        begin
          payment_source = ChargeBee::PaymentSource.retrieve(entry.customer.primary_payment_source_id)&.payment_source
        rescue StandardError => e
          puts "Error: #{e.message}"
        end
      end
    end

    subscription_statuses = subscriptions.map { |s| s[1][:status] }

    if (["active", "future"] & subscription_statuses).any?
      subscription_phase = MyLib::Account.subscription_phase(active_subscription, @user.skipped_first_box, {}, @user)

      if @user.subscription_phase_status != subscription_phase[:status]
        @user.update_columns(subscription_phase_status: subscription_phase[:status])
      end
    end

    render json: {
      subscription_phase: subscription_phase,
      shipping_address: shipping_address,
      billing_address: billing_address,
      payment_method: payment_method,
      payment_source: payment_source,
      card: card,
      orders: MyLib::Transaction.orders(user: @user, subscription: subscription, limit: 2, loopable: false)
    }, status: 200
  end

  # Route: /api/v1/user/dogs
  # Method: POST
  # Add dog by user
  def add_dog
  end

  # Route: /api/v1/user/notifications
  # Method: GET
  # Get user's notifications & promotions
  def notifications
  end
end
