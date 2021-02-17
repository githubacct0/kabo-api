# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApplicationController
  include Renderable

  # Route: /api/v1/user/subscriptions
  # Method: GET
  # Get user's subscriptions such as next delivery, plans, delivery frequencies
  def index
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
    dogs = @user.dogs

    MyLib::Chargebee.get_subscription_list(
      chargebee_customer_id: @user.chargebee_customer_id
    ).each do |chargebee_subscription|
      subscription = chargebee_subscription.subscription
      is_active = ["active", "future"].include? subscription.status
      active_subscription = subscription if is_active
      invoice = MyLib::Chargebee.get_invoice(subscription: subscription, statuses: ["active", "future"])
      invoice_estimate_total = invoice[:invoice_estimate_total]
      invoice_estimate_description = invoice[:invoice_estimate_description]

      subscriptions[subscription.id] = {
        dog_id: dogs.find { |dog| dog.chargebee_subscription_id == subscription.id }&.id,
        id: subscription.id,
        status: subscription.status,
        invoice_estimate_total: invoice_estimate_total,
        invoice_estimate_description: invoice_estimate_description,
        shipping_province: subscription.shipping_address.state_code,
        addons: subscription.addons&.map { |addon| { id: addon.id, unit_price: addon.unit_price, quantity: addon.quantity } }
      }
      card = chargebee_subscription.card
      shipping_address = subscription&.shipping_address
      subscription_created_at = subscription&.created_at
    end

    subscription_statuses = subscriptions.map { |s| s[1][:status] }

    @user.update_columns(subscription_phase_status: "normal_user_scheduled_order") if (["paused", "cancelled"] & subscription_statuses).any?

    subscription_phase = nil
    payment_method_icon = nil
    payment_method_details = nil
    total_paid = 0

    if (["active", "future"] & subscription_statuses).any?
      subscription_phase = MyLib::Account.subscription_phase(active_subscription, @user.skipped_first_box, {}, @user)

      @user.update_columns(subscription_phase_status: subscription_phase[:status]) if @user.subscription_phase_status != subscription_phase[:status]

      all_active_or_future_subscriptions_are_custom = (subscription_statuses.count { |x| x == "active" || x == "future" || x == "paused" } == @user.dogs.where(has_custom_plan: true).size)

      if subscription_phase[:status] == "waiting_for_trial_shipment" || subscription_phase[:status] == "waiting_for_resume_shipment"
        amounts_paid = []
        transaction_list_query = {
          "type[in]" => "['payment']",
          "customer_id[is]" => @user.chargebee_customer_id
        }
        if subscription_phase[:status] == "waiting_for_resume_shipment"
          # Get payment amount
          transaction_list_query["date[between]"] = [active_subscription.activated_at, active_subscription.activated_at + 2.days]
        else
          # Get payment amount
          transaction_list_query["date[between]"] = [subscription_created_at, subscription_created_at + 2.days]
        end

        transaction_list = ChargeBee::Transaction.list(transaction_list_query)

        transaction_list.each do |entry|
          transaction = entry.transaction
          amounts_paid.push(transaction.amount)
          payment_method_icon = case transaction.payment_method
                                when "paypal_express_checkout" then "paypal-logo"
                                when "apple_pay" then "apple-pay-logo"
                                else "generic-cc"
          end

          payment_method_details = ["paypal_express_checkout", "apple_pay"].include?(transaction.payment_method) ? "" : "Card ending in #{transaction.masked_card_number.last(4)}"
        end

        total_paid = Money.new(amounts_paid.sum).format
      end
    end
    subscription_start_date = MyLib::Icecube.subscription_start_date
    purchase_by_date = (Time.now + 2.days).strftime("%b %e, %Y")
    if Time.now + 2.days > (Time.zone.at(subscription_start_date))
      purchase_by_date = Time.zone.at(subscription_start_date).strftime("%b %e")
    end
    default_delivery_date = subscription_start_date + 7.days
    if !shipping_address.zip.nil?
      default_delivery_date = subscription_start_date + MyLib::Account.delivery_date_offset_by_postal_code(shipping_address.zip)
    end

    render json: {
      user: @user,
      dogs: dogs,
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
      next_occurrencies: MyLib::Icecube.subscription_next_occurrencies,
      skipped_first_box: @user.skipped_first_box
    }, status: :ok
  end

  # Route: /api/v1/user/subscriptions/pause
  # Method: POST
  # Pause user's dog's subscription
  def pause
    unless pause_subscriptions_params_valid?
      render_missed_params
    else
      pause_until = pause_subscriptions_params[:pause_until]

      dog = Dog.find_by_id(pause_subscriptions_params[:dog_id])
      if dog.present?
        pause_params = { pause_option: "immediately" }
        pause_until != "forever" && pause_params[:resume_date] = Time.parse(pause_until).utc.to_i
        # Pause subscription
        result = MyLib::Chargebee.pause_subscription(subscription_id: dog.chargebee_subscription_id, params: pause_params)

        if result[:status]
          render json: {
            subscription: result[:subscription]
          }, status: :ok
        else
          render json: {
            error: result[:error]
          }, status: :bad_request
        end
      else
        render json: {
          error: "Dog not exist!"
        }, status: :not_found
      end
    end
  end

  # Route: /api/v1/user/subscriptions/resume
  # Method: POST
  # Resume user's subscription
  def resume
    unless resume_subscriptions_params_valid?
      render_missed_params
    else
      dog = Dog.find_by_id(resume_subscriptions_params[:dog_id])

      if dog.present?
        dog_subscription = ChargeBee::Subscription.retrieve(dog.chargebee_subscription_id)&.subscription
        begin
          if ["paused", "cancelled"].include? dog_subscription.status
            if dog_subscription.status == "paused"
              result = MyLib::Chargebee.unpause_subscription(@user, dog)
            else
              result = MyLib::Chargebee.reactivate_subscription(@user, dog)
            end

            subscription_start_date = MyLib::Icecube.subscription_start_date

            default_delivery_date = subscription_start_date + 7.days
            if !result.subscription.shipping_address.zip.nil?
              default_delivery_date = subscription_start_date + MyLib::Account.delivery_date_offset_by_postal_code(result.subscription.shipping_address.zip)
            end

            UserMailer.with(
              user: @user,
              shipping_address: JSON.parse(result.subscription.shipping_address.to_s),
              subject: "Your subscription for #{dog.name} has been #{dog_subscription.status == 'paused' ? 'unpaused' : 'reactivated'}!",
              description: "Your next order will be delivered #{Time.zone.at(default_delivery_date).strftime("%b %e, %Y")}"
            ).resume_subscription_confirmation.deliver_later

            SlackWorker.perform_async(
              hook_url: Rails.configuration.slack_webhooks[:accountpage],
              text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{@user.email} has #{dog_subscription.status == 'paused' ? 'unpaused' : 'reactivated'} their subscription for #{dog.name}",
              icon_emoji: ":arrow_forward:"
            )

            AirtableWorker.perform_async(
              table_id: Rails.configuration.airtable[:subscription_resume_app_key],
              view_name: "Customers",
              record: {
                "Email": @user.email,
                "CB Customer ID": @user.chargebee_customer_id,
                "Province": result.subscription.shipping_address.state
              }
            )

            KlaviyoWorker.perform_async(
              list_id: "Wy22hD",
              email: @user.email
            )

            render json: {
              dog: dog
            }, status: :ok
          else
            render json: {
              error: "Your subscription is already active, please contact help@kabo.co if you're experiencing any issues"
            }, status: :ok
          end
        rescue StandardError => e
          Raven.capture_exception(e)

          render json: {
            error: e.message
          }, status: :internal_server_error
        end
      else
        render json: {
          error: "Dog not exist!"
        }, status: :not_found
      end
    end
  end

  # Route: /api/v1/user/subscriptions/cancel
  # Method: POST
  # Cancel user's dog's subscription
  def cancel
    unless cancel_subscriptions_params_valid?
      render_missed_params
    else
      dog = Dog.find_by_id(cancel_subscriptions_params[:dog_id])

      if dog.present?
        AirtableWorker.perform_async(
          table_id: Rails.configuration.airtable[:subscription_cancel_app_key],
          view_name: "Other",
          record: {
            "Email": @user.email,
            "CB Subscription ID": dog.chargebee_subscription_id,
            "CB Customer ID": @user.chargebee_customer_id,
            "Reason": "Other",
            "Date": DateTime.now.in_time_zone("Eastern Time (US & Canada)")
          }
        )

        # Cancel subscription
        result = MyLib::Chargebee.cancel_subscription(subscription_id: dog.chargebee_subscription_id)

        if result[:status]
          render json: {
            subscription: result[:subscription]
          }, status: :ok
        else
          render json: {
            error: result[:error]
          }, status: :bad_request
        end
      else
        render json: {
          error: "Dog not exist!"
        }, status: :not_found
      end
    end
  end

  # Route: /api/v1/user/subscriptions/meal_plans
  # Method: GET
  # Get meal plans
  def meal_plans
    render json: {
      cooked_recipes: Dog.cooked_recipes,
      kibble_recipes: Dog.kibble_recipes
    }, status: :ok
  end

  # Route: /api/v1/user/subscriptions/portions
  # Method: GET
  # Get daily portions
  def daily_portions
    unless daily_portions_params_valid?
      render_missed_params
    else
      dog = Dog.find_by_id(daily_portions_params[:dog_id])
      if dog.nil?
        render json: {
          error: "Dog does not exist!"
        }, status: :not_found
      else
        cooked_recipes = daily_portions_params[:cooked_recipes]
        kibble_recipe = daily_portions_params[:kibble_recipe]
        if kibble_recipe.present?
          if (cooked_recipes & ["beef", "chicken", "lamb", "turkey"]).any?
            portions = dog.mixed_cooked_and_kibble_recipe_daily_portions
          else
            portions = dog.only_kibble_recipe_daily_portions
          end
        else
          portions = dog.only_cooked_recipe_daily_portions(type: "frontend")
        end

        render json: {
          portions: portions
        }, status: :ok
      end
    end
  end

  # Route: /api/v1/user/subscriptions/meal_plan/estimate
  # Method: POST
  # Get estimate of meal plans
  def estimate_meal_plan
    dog = Dog.find_by(id: estimate_meal_plan_params[:dog_id])

    price_estimate = dog.price_estimate(estimate_meal_plan_params.except(:dog_id))

    render json: { amount: price_estimate }, status: :ok
  end

  # Route: /api/v1/user/subscriptions/meal_plan
  # Method: PUT
  # Update meal plan
  def update_meal_plan
    update_meal_plan_params = estimate_meal_plan_params

    dog = Dog.find_by_id(update_meal_plan_params[:dog_id])
    update_meal_plan_params[:id] = update_meal_plan_params.delete :dog_id

    if dog.present?
      new_portion_adjustment = update_meal_plan_params[:portion_adjustment]
      if dog.portion_adjustment != new_portion_adjustment
        MyLib::SlackNotifier.notify(
          webhook: Rails.configuration.slack_webhooks[:accountpage],
          text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{@user.email} adjusted their portion to #{new_portion_adjustment.present? ? new_portion_adjustment : "recommended"}",
          icon_emoji: ":shallow_pan_of_food:"
        )
      end

      # Update dog
      dog.update(update_meal_plan_params)

      if dog.chargebee_subscription_id.present? && !dog.has_custom_plan
        subscription_result = ChargeBee::Subscription.retrieve(dog.chargebee_subscription_id)

        if ["future", "active"].include?(subscription_result.subscription.status)
          MyLib::Chargebee.update_subscription(
            subscription_status: subscription_result.subscription.status,
            has_scheduled_changes: subscription_result.subscription.has_scheduled_changes,
            dog_chargebee_subscription_id: dog.chargebee_subscription_id,
            chargebee_plan_interval: @user.chargebee_plan_interval,
            addons: dog.subscription_param_addons,
            apply_coupon_statuses: ["future"]
          )

          MyLib::SlackNotifier.notify(
            webhook: Rails.configuration.slack_webhooks[:accountpage],
            text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{@user.email} changed their meaplan to #{dog.readable_mealplan}",
            icon_emoji: ":shallow_pan_of_food:"
          )
        end
      end

      render json: {
        dog: dog
      }, status: :ok
    else
      render json: {
        error: "Dog does not exist!"
      }, status: :not_found
    end
  end

  private
    def pause_subscriptions_params
      params.require(:subscription).permit(:dog_id, :pause_until)
    end

    def pause_subscriptions_params_valid?
      pause_subscriptions_params[:dog_id].present? &&
        pause_subscriptions_params[:pause_until].present?
    end

    def resume_subscriptions_params
      params.require(:subscription).permit(:dog_id)
    end

    def resume_subscriptions_params_valid?
      resume_subscriptions_params[:dog_id].present?
    end

    def daily_portions_params
      params.require(:subscription).permit(:dog_id, :kibble_recipe, cooked_recipes: [])
    end

    def daily_portions_params_valid?
      daily_portions_params[:dog_id].present? &&
        (["cooked_recipes", "kibble_recipe"] & daily_portions_params.keys).any?
    end

    def estimate_meal_plan_params
      params.require(:subscription).permit(
        :dog_id,
        :chicken_recipe,
        :beef_recipe,
        :turkey_recipe,
        :lamb_recipe,
        :kibble_recipe,
        :cooked_portion,
        :kibble_portion,
        :portion_adjustment
      )
    end

    def cancel_subscriptions_params
      params.require(:subscription).permit(:dog_id)
    end

    def cancel_subscriptions_params_valid?
      cancel_subscriptions_params[:dog_id].present?
    end
end
