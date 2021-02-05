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
          status: true
        }, status: 200
      else
        render json: {
          status: false,
          err: "Dog not exist!"
        }, status: 500
      end
    else
      render json: {
        status: false,
        err: "Missed params!"
      }, status: 500
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
            result = ChargebeeHelper.unpause_subscription(@user, dog)
          else
            result = ChargebeeHelper.reactivate_subscription(@user, dog)
          end

          subscription_start_date = IceCubeHelper.subscription_start_date

          default_delivery_date = subscription_start_date + 7.days
          if !result.subscription.shipping_address.zip.nil?
            default_delivery_date = subscription_start_date + AccountHelper.delivery_date_offset_by_postal_code(result.subscription.shipping_address.zip)
          end

          UserMailer.with(
            user: @user,
            shipping_address: JSON.parse(result.subscription.shipping_address.to_s),
            subject: "Your subscription for #{dog.name} has been #{dog_subscription.status == 'paused' ? 'unpaused' : 'reactivated'}!",
            description: "Your next order will be delivered #{Time.zone.at(default_delivery_date).strftime("%b %e, %Y")}"
          ).resume_subscription_confirmation.deliver_later

          SlackWorker.perform_async(
            hook_url: Rails.configuration.slack_webhooks[:accountpage],
            text: "#{ ('[' + ENV['HEROKU_APP_NAME'] + '] ') if ENV['HEROKU_APP_NAME'] != 'kabo-app' }#{@user.email} has #{dog_subscription.status == 'paused' ? 'unpaused' : 'reactivated'} their subscription for #{dog.name}",
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
            status: true
          }, status: 200
        else
          render json: {
            status: false,
            err: "Your subscription is already active, please contact help@kabo.co if you're experiencing any issues"
          }, status: 200
        end
      rescue StandardError => e
        Raven.capture_exception(e)

        render json: {
          status: false,
          err: e.message
        }, status: 500
      end
    else
      render json: {
        status: false,
        err: "Dog not exist!"
      }, status: 500
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
          status: true
        }, status: 200
      rescue => e
        Raven.capture_exception(e)

        render json: {
          status: false
        }, status: 500
      end
    else
      render json: {
        status: false,
        err: "Dog not exist!"
      }, status: 500
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
end