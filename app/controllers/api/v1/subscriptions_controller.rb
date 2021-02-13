# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApplicationController
  # Route: /api/v1/user/subscriptions/pause
  # Method: POST
  # Pause user's dog's subscription
  def pause
    if pause_subscriptions_params_valid?
      pause_until = pause_subscriptions_params[:pause_until]

      dog = Dog.find_by_id(pause_subscriptions_params[:dog_id])
      if dog.present?
        pause_params = { pause_option: "immediately" }
        pause_until != "forever" && pause_params[:resume_date] = Time.parse(pause_until).utc.to_i
        ChargeBee::Subscription.pause(dog.chargebee_subscription_id, pause_params)

        render json: {
          dog: dog
        }, status: :ok
      else
        render json: {
          error: "Dog not exist!"
        }, status: :not_found
      end
    else
      render json: {
        error: "Missed params!"
      }, status: :bad_request
    end
  end

  # Route: /api/v1/user/subscriptions/resume
  # Method: POST
  # Resume user's subscription
  def resume
    dog = Dog.find_by_id(pause_subscriptions_params[:dog_id])

    if dog.present?
      cb_dog_subscription = ChargeBee::Subscription.retrieve(dog.chargebee_subscription_id)
      dog_subscription = cb_dog_subscription.subscription
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

  # Route: /api/v1/user/subscriptions/cancel
  # Method: POST
  # Cancel user's dog's subscription
  def cancel
    dog = Dog.find_by_id(pause_subscriptions_params[:dog_id])

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

      begin
        ChargeBee::Subscription.cancel(dog.chargebee_subscription_id)

        render json: {
          dog: dog
        }, status: :ok
      rescue => e
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

  # Route: /api/v1/user/subscriptions/meal_plans
  # Method: GET
  # Get meal plans
  def meal_plans
    render json: {
      cooked_recipes: MyLib::Account.cooked_recipes,
      kibble_recipes: MyLib::Account.kibble_recipes
    }, status: :ok
  end

  # Route: /api/v1/user/subscriptions/portions
  # Method: GET
  # Get daily portions
  def daily_portions
    portions = []
    cooked_recipes = daily_portions_params[:cooked_recipes]
    kibble_recipe = daily_portions_params[:kibble_recipe]
    dog_name = daily_portions_params[:dog_name]
    if kibble_recipe.present?
      if (cooked_recipes & ["beef", "chicken", "lamb", "turkey"]).any?
        portions = MyLib::Account.mixed_cooked_and_kibble_recipe_daily_portions
      else
        portions = MyLib::Account.only_kibble_recipe_daily_portions(name: dog_name)
      end
    else
      portions = MyLib::Account.only_cooked_recipe_daily_portions(name: dog_name)
    end

    render json: {
      portions: portions
    }, status: :ok
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
      params.permit(:dog_id, :pause_until)
    end

    def pause_subscriptions_params_valid?
      pause_subscriptions_params[:pause_until].present? &&
        pause_subscriptions_params[:dog_id].present?
    end

    def resume_subscriptions_params
      params.permit(:dog_id)
    end

    def resume_subscriptions_params_valid?
      resume_subscriptions_params[:dog_id].present?
    end

    def verified_user_params
      params.require(:user).permit(
        :email,
        :chargebee_plan_interval,
        :shipping_first_name,
        :shipping_last_name,
        :shipping_street_address,
        :shipping_apt_suite,
        :shipping_city,
        :shipping_postal_code,
        :shipping_phone_number,
        :shipping_delivery_instructions,
        :same_billing_address,
        :billing_first_name,
        :billing_last_name,
        :billing_street_address,
        :billing_apt_suite,
        :billing_city,
        :billing_postal_code,
        :billing_phone_number,
        :password,
        :password_confirmation,
        :stripe_token,
        :stripe_type,
        :reference_id,
        :referral_code,
        dogs_attributes: [:id, :meal_type, :kibble_type])
    end

    def daily_portions_params
      params.permit(:dog_name, :kibble_recipe, cooked_recipes: [])
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
end
