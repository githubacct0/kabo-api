# frozen_string_literal: true

class Api::V1::UsersController < ApplicationController
  include Renderable

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
      starting_date = Time.parse(update_delivery_frequency_params[:starting_date]).utc.to_i

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
            MyLib::Chargebee.update_subscription(
              subscription_status: subscription_result.subscription.status,
              has_scheduled_changes: subscription_result.subscription.has_scheduled_changes,
              dog_chargebee_subscription_id: dog.chargebee_subscription_id,
              chargebee_plan_interval: meal_type,
              addons: dog.subscription_param_addons,
              apply_coupon_statuses: ["active", "future"]
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

      notifier = Slack::Notifier.new Rails.configuration.slack_webhooks[:accountpage]
      MyLib::SlackNotifier.notify(
        notifier: notifier,
        text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{@user.email} changed their delivery frequency from #{original_chargebee_plan_interval} to #{submitted_meal_type}",
        icon_emoji: ":shallow_pan_of_food:"
      ) if original_chargebee_plan_interval != meal_type
      MyLib::SlackNotifier.notify(
        notifier: notifier,
        text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{@user.email} changed their next billing date from #{Time.zone.at(original_next_billing_date)} to #{Time.zone.at(starting_date)}",
        icon_emoji: ":shallow_pan_of_food:"
      ) if original_next_billing_date

      render json: {
        user: @user
      }, status: :ok
    else
      render_missed_params
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

    MyLib::Chargebee.get_subscription_list(
      chargebee_customer_id: @user.chargebee_customer_id
    ).each do |chargebee_subscription|
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
    }, status: :ok
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
    if update_password_params_valid?
      begin
        @user.update!(update_password_params)
        render json: {
          token: encode_token({ user_id: @user.id })
        }, status: :ok
      rescue => err
        validation_failed = "Validation failed:"
        errors = err.message.sub(validation_failed, "") if err.message.include? validation_failed
        render json: {
          error: errors&.split(",")&.map(&:strip)
        }, status: :bad_request
      end
    else
      render_missed_params
    end
  end

  # Route: /api/v1/user/delivery_address
  # Method: PUT
  # Update user's delivery address
  def update_delivery_address
    unless update_delivery_address_params_valid?
      render_missed_params
    else
      delivery_address_params = update_delivery_address_params
      shipping_address = billing_address = nil, nil
      chargebee_subscription_list = MyLib::Chargebee.get_subscription_list(chargebee_customer_id: @user.chargebee_customer_id)
      chargebee_subscription_list.each do |entry|
        shipping_address = entry.subscription.shipping_address
        billing_address = entry.customer.billing_address
      end
      delivery_address_params[:shipping_phone_number] = shipping_address.phone

      # Update shipping address
      begin
        @user.update!(delivery_address_params)
        MyLib::Chargebee.update_customer_and_subscription(@user)

        render json: {
          status: true
        }, status: :ok
      rescue => e
        Raven.capture_exception(e)
        render json: {
          error: e.message
        }, status: :bad_request
      end
    end
  end

  # Route: /api/v1/user/payment_method
  # Method: PUT
  # Update user's payment method
  def change_payment_method
    unless change_payment_method_params_valid?
      render_missed_params
    else
      shipping_address = billing_address = nil, nil
      chargebee_subscription_list = MyLib::Chargebee.get_subscription_list(chargebee_customer_id: @user.chargebee_customer_id)
      chargebee_subscription_list.each do |entry|
        shipping_address = entry.subscription.shipping_address
        billing_address = entry.customer.billing_address
      end

      shipping_mapping = address_mapping(type: "shipping")
      payment_method_params = change_payment_method_params
      shipping_mapping.each do |key1, key2|
        payment_method_params["shipping_#{key1}"] = shipping_address.try(key2)
      end

      # Update billing address as the same as shipping address
      if payment_method_params["same_as_shipping_address"]
        billing_mapping = address_mapping(type: "billing")
        billing_mapping.each do |key1, key2|
          payment_method_params["billing_#{key1}"] = billing_address.try(key2)
        end
      end

      begin
        # Update billing address
        @user.update!(payment_method_params)
        # Update subscription
        MyLib::Chargebee.update_customer_and_subscription(@user)

        render json: {
          status: true
        }, status: :ok
      rescue => e
        Raven.capture_exception(e)
        render json: {
          error: e.message
        }, status: :bad_request
      end
    end
  end

  # Route: /api/v1/user/apply_coupon
  # Method: POST
  # Apply coupon
  def apply_coupon
    if coupon_code_params_valid?
      coupon_code = coupon_code_params[:coupon_code]
      # Apply coupon code
      begin
        @user.dogs.each { |dog| ChargeBee::Subscription.update(dog.chargebee_subscription_id, { coupon_ids: [coupon_code] }) }

        # Get subscriptions
        subscriptions = {}
        MyLib::Chargebee.get_subscription_list(
          chargebee_customer_id: @user.chargebee_customer_id
        ).each  do |chargebee_subscription|
          subscription = chargebee_subscription.subscription
          invoice = MyLib::Chargebee.get_invoice(subscription: subscription, statuses: ["active", "future"])
          invoice_estimate_total = invoice[:invoice_estimate_total]
          invoice_estimate_description = invoice[:invoice_estimate_description]
          subscriptions[subscription.id] = {
            id: subscription.id,
            status: subscription.status,
            invoice_estimate_total: invoice_estimate_total,
            invoice_estimate_description: invoice_estimate_description,
            shipping_province: subscription.shipping_address.state_code,
            addons: subscription.addons&.map { |addon| { id: addon.id, unit_price: addon.unit_price, quantity: addon.quantity } }
          }
        end

        render json: {
          subscriptions: subscriptions
        }, status: :ok
      rescue StandardError => e
        Raven.capture_exception(e)

        render json: {
          error: "Invalid coupon code!"
        }, status: :bad_request
      end
    else
      render_missed_params
    end
  end

  private
    def update_password_params
      params.permit(:password, :password_confirmation)
    end

    def update_delivery_frequency_params
      params.permit(:amount_of_food, :how_often, :starting_date)
    end

    def coupon_code_params
      params.permit(:coupon_code)
    end

    def update_delivery_address_params
      params.permit(
        :shipping_first_name,
        :shipping_last_name,
        :shipping_street_address,
        :shipping_apt_suite,
        :shipping_city,
        :shipping_postal_code,
        :shipping_delivery_instructions
      )
    end

    def change_payment_method_params
      params.permit(
        :stripe_token,
        :same_as_shipping_address,
        :billing_first_name,
        :billing_last_name,
        :billing_street_address,
        :billing_apt_suite,
        :billing_city,
        :billing_postal_code,
        :billing_phone_number
      )
    end

    def update_password_params_valid?
      update_password_params[:password].present? &&
        update_password_params[:password_confirmation]
    end

    def update_delivery_frequency_params_valid?
      update_delivery_frequency_params[:amount_of_food].present? &&
        update_delivery_frequency_params[:how_often].present? &&
        update_delivery_frequency_params[:starting_date].present?
    end

    def coupon_code_params_valid?
      coupon_code_params[:coupon_code]
    end

    def update_delivery_address_params_valid?
      update_delivery_address_params[:shipping_first_name].present? &&
        update_delivery_address_params[:shipping_last_name].present? &&
        update_delivery_address_params[:shipping_street_address].present? &&
        # update_delivery_address_params[:shipping_apt_suite].present? &&
        update_delivery_address_params[:shipping_city].present? &&
        update_delivery_address_params[:shipping_postal_code].present?
      # update_delivery_address_params[:shipping_delivery_instructions].present?
    end

    def change_payment_method_params_valid?
      change_payment_method_params[:stripe_token].present? &&
        change_payment_method_params.key?("same_as_shipping_address")
    end

    def address_mapping(type:)
      mapping = {
        "first_name": "first_name",
        "last_name": "last_name",
        "street_address": "line1",
        "apt_suite": "line2",
        "city": "city",
        "postal_code": "zip",
      }

      mapping[:delivery_instructions] = "line3" if type == "shipping"
      mapping[:phone_number] = "phone" if type == "billing"

      mapping
    end
end
