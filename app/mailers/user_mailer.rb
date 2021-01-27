# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def skip_box
    user = params[:user]
    subscription_phase = params[:subscription_phase]

    @first_name = user.first_name
    @body_text = "Your #{subscription_phase[:date].strftime("%B %e")} shipment has been skipped. Your next order is queued for #{subscription_phase[:skip_date].strftime("%B %e")}, you will get an email beforehand in case you need to make any more changes."
    mail(to: user.email, subject: "Your #{subscription_phase[:date].strftime("%B %e")} shipment has been skipped")
  end

  def one_time_purchase_order_confirmation
    @user = params[:user]
    @invoice = params[:invoice]

    mail(to: @user.one_time_purchase_email, subject: "Congrats on your Kabo order #{@user.first_name}!")
  end

  def one_time_purchase_receipt
    user = params[:user]

    @first_name = user.first_name
    @body_text = "Your purchase receipt is available at #{checkout_v2_success_url(user.checkout_token)}"
    mail(to: user.one_time_purchase_email, subject: "Your Kabo Purchase")
  end

  def upsell_order_confirmation
    @user = params[:user]
    @invoice = params[:invoice]
    @quantity = params[:quantity]
    @total = params[:total]
    @product_description = params[:description]

    mail(to: @user.email, subject: "Order Confirmation - #{params[:subject]}")
  end

  def resume_subscription_confirmation
    @user = params[:user]
    @shipping_address = params[:shipping_address]
    @quantity = params[:quantity]
    @total = params[:total]
    @product_description = params[:description]

    mail(to: @user.email, subject: params[:subject])
  end
end
