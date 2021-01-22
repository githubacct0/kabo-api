# frozen_string_literal: true

class Api::V1::UsersController < ApplicationController
  # Route: "/api/v1/users/details"
  # Get user"s details
  def details
    if session_user
      if @user.trial
        schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        first_shipment_date = (schedule.next_occurrence(@user.created_at).utc + 7.days).strftime("%b %e")
        checkout_price_total = MyLib::Checkout.estimate_trial[:priceTotal][:details][1..-1]

        render json: {
          trial: true,
          first_shipment_date: first_shipment_date,
          checkout_price_total: checkout_price_total
        }
      else
        if Rails.configuration.heroku[:app_name] != "kabo-app" && Rails.configuration.heroku[:app_name] != "kabo-beta" && !params[:qa_jump_by_days].blank?
          @user.update_columns(qa_jump_by_days: params[:qa_jump_by_days])
        end

        subscription_list = ChargeBee::Subscription.list({
          "customer_id[is]" => @user.chargebee_customer_id
        })

        subscriptions = {}
        subscription = subscription_list.last.subscription
        shipping_address = subscription&.shipping_address
        subscription_created_at = subscription&.created_at
        active_subscription = nil

        subscription_list.each do |entry|
          subscriptions[entry.subscription.id] = {
            id: entry.subscription.id,
            status: entry.subscription.status,
            invoice_estimate_total: (entry.subscription.status == "active" || entry.subscription.status == "future") ? ChargeBee::Estimate.renewal_estimate(entry.subscription.id).estimate.invoice_estimate.total : "N/A",
            invoice_estimate_description: (entry.subscription.status == "active" || entry.subscription.status == "future") ? ChargeBee::Estimate.renewal_estimate(entry.subscription.id).estimate.invoice_estimate.line_items.select { |li| li.subscription_id == entry.subscription.id }[0].description : "N/A",
            shipping_province: entry.subscription.shipping_address.state_code,
            addons: entry.subscription.addons ? entry.subscription.addons.map { |addon| { id: addon.id, unit_price: addon.unit_price, quantity: addon.quantity } } : []
          }

          active_subscription = entry.subscription if entry.subscription.status == "active" || entry.subscription.status == "future"
        end

        subscription_statuses = subscriptions.map { |s| s[1][:status] }

        if (["paused", "cancelled"] & subscription_statuses).any?
          current_user.update_columns(subscription_phase_status: "normal_user_scheduled_order")
        end

        subscription_phase = nil
        payment_method_icon = nil
        payment_method_details = nil
        total_paid = 0

        if (["active", "future"] & subscription_statuses).any?
          subscription_phase = MyLib::Account.subscription_phase(active_subscription, current_user.skipped_first_box, {}, current_user)

          if current_user.subscription_phase_status != subscription_phase[:status]
            current_user.update_columns(subscription_phase_status: subscription_phase[:status])
          end

          all_active_or_future_subscriptions_are_custom = (subscription_statuses.count { |x| x == "active" || x == "future" || x == "paused" } == current_user.dogs.where(has_custom_plan: true).count)

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
          trial: false,
          subscriptions: subscriptions,
          subscription: subscription,
          active_subscription: active_subscription,
          subscription_phase: subscription_phase,
          payment_method_icon: payment_method_icon,
          payment_method_details: payment_method_details,
          total_paid: total_paid,
          purchase_by_date: purchase_by_date,
          default_delivery_date: default_delivery_date,
          starting_date: active_subscription ? active_subscription.next_billing_at : nil,
          all_active_or_future_subscriptions_are_custom: all_active_or_future_subscriptions_are_custom
        }
      end
    else
      render json: {
        errors: "No User Logged In"
      }
    end
  end
end
