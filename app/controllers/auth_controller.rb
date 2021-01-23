# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :require_login, only: [:login]
  def login
    user = User.find_by(email: params[:email])
    if user && user.valid_password?(params[:password])
      payload = { user_id: user.id }
      token = encode_token(payload)

      # Update qa_jump_by_days
      if ["kabo-app", "kabo-beta"].exclude?(Rails.configuration.heroku_app_name) && params[:qa_jump_by_days].present?
        user.update_columns(qa_jump_by_days: params[:qa_jump_by_days])
      end

      # Get Subscriptions
      subscriptions = {}
      subscription = {}
      active_subscription = nil
      shipping_address = nil
      subscription_created_at = nil
      card = {}

      chargebee_subscriptions = ChargeBee::Subscription.list({
        "customer_id[is]" => user.chargebee_customer_id
      })
      chargebee_subscriptions.each do |chargebee_subscription|
        subscription = chargebee_subscription.subscription
        active_subscription = subscription if ["active", "future"].include? subscription.status
        subscriptions[subscription.id] = {
          id: subscription.id,
          status: subscription.status,
          invoice_estimate_total: (subscription.status == "active" || subscription.status == "future") ? ChargeBee::Estimate.renewal_estimate(subscription.id).estimate.invoice_estimate.total : "N/A",
          invoice_estimate_description: (subscription.status == "active" || subscription.status == "future") ? ChargeBee::Estimate.renewal_estimate(subscription.id).estimate.invoice_estimate.line_items.select { |li| li.subscription_id == subscription.id }[0].description : "N/A",
          shipping_province: subscription.shipping_address.state_code,
          addons: subscription.addons ? subscription.addons.map { |addon| { id: addon.id, unit_price: addon.unit_price, quantity: addon.quantity } } : []
        }
        card = chargebee_subscription.card
        shipping_address = subscription&.shipping_address
        subscription_created_at = subscription&.created_at
      end

      subscription_statuses = subscriptions.map { |s| s[1][:status] }

      if (["paused", "cancelled"] & subscription_statuses).any?
        user.update_columns(subscription_phase_status: "normal_user_scheduled_order")
      end

      subscription_phase = nil
      payment_method_icon = nil
      payment_method_details = nil
      total_paid = 0

      if (["active", "future"] & subscription_statuses).any?
        subscription_phase = MyLib::Account.subscription_phase(active_subscription, user.skipped_first_box, {}, user)

        if user.subscription_phase_status != subscription_phase[:status]
          user.update_columns(subscription_phase_status: subscription_phase[:status])
        end

        all_active_or_future_subscriptions_are_custom = (subscription_statuses.count { |x| x == "active" || x == "future" || x == "paused" } == user.dogs.where(has_custom_plan: true).count)

        if subscription_phase[:status] == "waiting_for_trial_shipment" || subscription_phase[:status] == "waiting_for_resume_shipment"
          amounts_paid = []
          payment_method_icon = "generic-cc"

          if subscription_phase[:status] == "waiting_for_resume_shipment"
            # Get payment amount
            list = ChargeBee::Transaction.list({
              "type[in]" => "['payment']",
              "customer_id[is]" => @user.chargebee_customer_id,
              "date[between]" => [active_subscription.activated_at, active_subscription.activated_at + 2.days], # 2.day buffer incase someone makes an upsell purchase
            })
          else
            # Get payment amount
            list = ChargeBee::Transaction.list({
              "type[in]" => "['payment']",
              "customer_id[is]" => @user.chargebee_customer_id,
              "date[between]" => [subscription_created_at, subscription_created_at + 2.days], # 2.day buffer incase someone makes an upsell purchase
            })
          end

          list.each do |entry|
            amounts_paid.push(entry.transaction.amount)
            if entry.transaction.payment_method == "paypal_express_checkout"
              payment_method_icon = "paypal-logo"
            elsif entry.transaction.payment_method == "apple_pay"
              payment_method_icon = "apple-pay-logo"
            else
              payment_method_icon = "generic-cc"
            end

            payment_method_details = ["paypal_express_checkout", "apple_pay"].include?(entry.transaction.payment_method) ? "" : "Card ending in #{entry.transaction.masked_card_number.last(4)}"
          end

          total_paid = Money.new(amounts_paid.sum).format
        end
      end

      schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
        s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
      end
      subscription_start_date = schedule.next_occurrence.utc.to_i
      purchase_by_date = (Time.now + 2.days).strftime("%b %e, %Y")
      if Time.now + 2.days > (Time.zone.at(subscription_start_date))
        purchase_by_date = Time.zone.at(subscription_start_date).strftime("%b %e")
      end
      default_delivery_date = subscription_start_date + 7.days
      if !shipping_address.zip.nil?
        default_delivery_date = subscription_start_date + MyLib::Account.delivery_date_offset_by_postal_code(shipping_address.zip)
      end

      render json: {
        token: token,
        user: user,
        dogs: user.dogs,
        # Subscriptions
        subscriptions: subscriptions,
        subscription: subscription,
        active_subscription: active_subscription,
        subscription_phase: subscription_phase,
        card: card,
        payment_method_icon: payment_method_icon,
        payment_method_details: payment_method_details,
        total_paid: total_paid,
        purchase_by_date: purchase_by_date,
        default_delivery_date: default_delivery_date,
        starting_date: active_subscription ? active_subscription.next_billing_at : nil,
        all_active_or_future_subscriptions_are_custom: all_active_or_future_subscriptions_are_custom,

        success: "Welcome back, #{user.first_name}!"
      }, status: 200
    else
      render json: { error: "Invalid Email or Password!" }, status: 200
    end
  end
end
