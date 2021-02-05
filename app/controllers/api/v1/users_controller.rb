# frozen_string_literal: true

class Api::V1::UsersController < ApplicationController
  # Route: /api/v1/user/account
  # Method: GET
  # Get user's next delivery, plans, delivery frequencies
  def account
    # Update qa_jump_by_days
    if ["kabo-app", "kabo-beta"].exclude?(Rails.configuration.heroku_app_name) && params[:qa_jump_by_days].present?
      @user.update_columns(qa_jump_by_days: params[:qa_jump_by_days])
    end

    # Get Subscriptions
    subscriptions = {}
    subscription = {}
    active_subscription = nil
    shipping_address = nil
    subscription_created_at = nil
    card = {}

    chargebee_subscriptions = ChargeBee::Subscription.list({
      "customer_id[is]" => @user.chargebee_customer_id
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
      @user.update_columns(subscription_phase_status: "normal_user_scheduled_order")
    end

    subscription_phase = nil
    payment_method_icon = nil
    payment_method_details = nil
    total_paid = 0

    if (["active", "future"] & subscription_statuses).any?
      subscription_phase = MyLib::Account.subscription_phase(active_subscription, @user.skipped_first_box, {}, @user)

      if @user.subscription_phase_status != subscription_phase[:status]
        @user.update_columns(subscription_phase_status: subscription_phase[:status])
      end

      all_active_or_future_subscriptions_are_custom = (subscription_statuses.size { |x| x == "active" || x == "future" || x == "paused" } == @user.dogs.where(has_custom_plan: true).size)

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
      dogs: @user.dogs,
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
      # Next occurencies for pause plans
      next_occurrencies: MyLib::Icecube.subscription_next_occurrencies
    }, status: 200
  end

  # Route: /api/v1/user/delivery_frequency
  # Method: PUT
  # Update user's delivery frequency
  def update_delivery_frequency
    if update_delivery_frequency_params_valid?
      # Get delivery frequency params
      amount_of_food = update_delivery_frequency_params[:amount_of_food]
      how_often = update_delivery_frequency_params[:how_often]
      how_often = "#{amount_of_food.split("_")[0]}_weeks" if amount_of_food.split("_")[0] == how_often.split("_")[0]
      meal_type = [amount_of_food, how_often].uniq.join("_")
      starting_date = update_delivery_frequency_params[:start_date].to_i

      original_chargebee_plan_interval = @user.chargebee_plan_interval
      original_next_billing_date = nil

      # Update chargebee plan
      @user.update({
        chargebee_plan_interval: meal_type
      })

      # Update dogs
      dogs = @user.dogs
      dogs.each do |dog|
        if dog.chargebee_subscription_id.present? && !dog.has_custom_plan
          subscription_result = ChargeBee::Subscription.retrieve(dog.chargebee_subscription_id)

          if ["future", "active"].include?(subscription_result.subscription.status)
            # add addon for lower AOV customers, only if the customer has 1 dog
            subscription_param_addons = []
            if dogs.size == 1 && dog.kibble_portion.blank? && dog.plan_units_v2(true) < @user.plan_unit_fee_limit
              subscription_param_addons.push(
                {
                  id: "delivery-service-fee-#{@user.how_often.split("_")[0]}-weeks"
                }
              )
            end

            # Recurring Addons
            dog_plan_units_v2 = dog.plan_units_v2
            dog.beef_recipe && subscription_param_addons.push(dog.subscription_recurring_addon("beef", meal_type, dog_plan_units_v2))
            dog.chicken_recipe && subscription_param_addons.push(dog.subscription_recurring_addon("chicken", meal_type, dog_plan_units_v2))
            dog.turkey_recipe && subscription_param_addons.push(dog.subscription_recurring_addon("turkey", meal_type, dog_plan_units_v2))
            dog.lamb_recipe && subscription_param_addons.push(dog.subscription_recurring_addon("lamb", meal_type, dog_plan_units_v2))
            subscription_param_addons.push({
              id: "#{dog.kibble_recipe}_kibble_#{meal_type}",
              quantity: dog.kibble_quantity_v2
            }) if dog.kibble_recipe.present?

            MyLib::Chargebee.update_subscription(
              subscription_status: subscription_result.subscription.status,
              has_scheduled_changes: subscription_result.subscription.has_scheduled_changes,
              dog_chargebee_subscription_id: dog.chargebee_subscription_id,
              chargebee_plan_interval: meal_type,
              addons: subscription_param_addons
            )

            if subscription_result.subscription.next_billing_at != starting_date
              original_next_billing_date = subscription_result.subscription.next_billing_at
              # Verify starting date submitted is a valid option
              schedule_to_verify_starting_date = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
                s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
              end

              schedule_to_verify_starting_date_timestamps = schedule_to_verify_starting_date.next_occurrences(3, Time.zone.now).map { |date| date.to_i }

              if schedule_to_verify_starting_date_timestamps.include?(starting_date) ||
                (Rails.configuration.heroku_app_name != "kabo-app" && Rails.configuration.heroku_app_name != "kabo-beta" && @user.qa_jump_by_days > 0)
                ChargeBee::Subscription.change_term_end(dog.chargebee_subscription_id, {
                  term_ends_at: starting_date
                })
              end
            end
          end

        end
      end

      if Rails.env.production?
        begin
          notifier = Slack::Notifier.new Rails.configuration.slack_webhooks[:accountpage]
          notifier.post(
            text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{@user.email} changed their delivery frequency from #{original_chargebee_plan_interval} to #{submitted_meal_type}",
            icon_emoji: ":shallow_pan_of_food:"
          ) if original_chargebee_plan_interval != meal_type
          notifier.post(
            text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{@user.email} changed their next billing date from #{Time.zone.at(original_next_billing_date)} to #{Time.zone.at(starting_date)}",
            icon_emoji: ":shallow_pan_of_food:"
          ) if original_next_billing_date
        rescue StandardError => e
          Raven.capture_exception(e)
        end
      end

      render json: {
        status: true
      }, status: 200
    else
      render json: {
        status: false,
        err: "Missed params!"
      }, status: 500
    end
  end

  # Route: /api/v1/user/subscriptions/pause
  # Method: POST
  # Pause subscriptions
  def pause_subscriptions
    if pause_subscriptions_params_valid?
      pause_until = pause_subscriptions_params[:pause_until]

      @user.dogs.each { |dog|
        pause_params = { pause_option: "immediately" }
        pause_until != "forever" && pause_params[:resume_date] = Time.parse(pause_until).utc.to_i
        ChargeBee::Subscription.pause(dog.chargebee_subscription_id, pause_params)
      }

      render json: {
        status: true
      }, status: 200
    else
      render json: {
        status: false,
        err: "Missed params!"
      }, status: 500
    end
  end

  # Route: /api/v1/user/details
  # Method: GET
  # Get user's account_details, billing, delivery_address, last 2 order
  def details
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

  # Route: /api/v1/user/password
  # Method: PUT
  # Update user's password
  def update_password
    status = @user.update(update_password_params)

    render json: {
      status: status
    }, status: 200
  rescue => err
    render json: {
      status: false,
      err: err.message
    }, status: 500
  end

  # Route: /api/v1/user/delivery_address
  # Method: PUT
  # Update user's delivery address
  def update_delivery_address
  end

  private
    def update_password_params
      params.permit(:password, :password_confirmation)
    end

    def update_delivery_frequency_params
      params.permit(:amount_of_food, :how_often, :starting_date)
    end

    def update_delivery_frequency_params_valid?
      update_delivery_frequency_params[:amount_of_food].present? &&
        update_delivery_frequency_params[:how_often].present? &&
        update_delivery_frequency_params[:starting_date].present?
    end

    def pause_subscriptions_params
      params.permit(:pause_until)
    end

    def pause_subscriptions_params_valid?
      pause_subscriptions_params[:pause_until].present?
    end
end