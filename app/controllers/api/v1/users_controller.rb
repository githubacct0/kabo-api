# frozen_string_literal: true

class Api::V1::UsersController < ApplicationController
  # Route: /api/v1/user
  # Method: GET
  # Get user's account_details, billing, delivery_address
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
      orders: orders(subscription: subscription)
    }, status: 200
  end

  # Route: /api/v1/user/dogs
  # Method: POST
  # Add dog by user
  def add_dog
  end

  private
    def orders(subscription:)
      next_offset = nil
      all_transactions_list = []
      all_invoices_list = []
      invoices = {}

      # Invoices
      loop do
        invoice_list_query = {
          "customer_id[is]" => @user.chargebee_customer_id,
          "sort_by[asc]" => "date",
          limit: 100
        }
        invoice_list_query[:offset] = next_offset if next_offset.present?

        result = ChargeBee::Invoice.list(invoice_list_query)
        all_invoices_list = result&.map { |invoice| invoice }
        next_offset = result.next_offset

        break if next_offset.nil?
      end
      all_invoices_list.each { |invoice| invoices[invoice.invoice.id] = invoice }

      # Transactions
      loop do
        transaction_list_query = {
          "customer_id[is]" => @user.chargebee_customer_id,
          "sort_by[asc]" => "date",
          "status[is]" => "success",
          limit: 100
        }
        transaction_list_query[:offset] = next_offset if next_offset.present?

        result = ChargeBee::Transaction.list(transaction_list_query)
        all_transactions_list = result&.map { |transaction| transaction }
        next_offset = result.next_offset

        break if next_offset.nil?
      end

      orders = all_transactions_list.map { |_transaction|
        transaction_histories(transaction: _transaction.transaction, subscription: subscription, invoices: invoices)
      }&.reverse

      orders
    rescue StandardError => e
      Raven.capture_exception(e)
      []
    end

    def payment_method_name(transaction)
      case transaction.payment_method
      when "paypal_express_checkout" then "PayPal"
      when "apple_pay" then "Apple Pay"
      else "Card #{transaction.masked_card_number.last(4)}"
      end
    end

    def transaction_histories(transaction:, subscription:, invoices:)
      payment_method_name = payment_method_name(transaction)
      history = {
        date_timestamp: transaction.date,
        date: Time.zone.at(transaction.date).strftime("%A %b %d"),
        date_mobile: Time.zone.at(transaction.date).strftime("%a %b %d"),
        total: Money.new(transaction.amount).format,
        card: payment_method_name,
        payment_status: transaction.type == "payment" ? "Paid" : transaction.type.humanize,
      }

      if transaction.type == "payment"
        invoice = transaction.linked_invoices[0]
        schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) { |s| s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday) }
        invoice_delivery_date = schedule.next_occurrence(Time.zone.at(invoice.invoice_date)) + MyLib::Account.delivery_date_offset(subscription)
        delivery_date_text = invoice_delivery_date > Time.now ? "Delivers" : "Delivered"

        history[:delivery_date] = "#{delivery_date_text} #{(invoice_delivery_date).strftime('%b %d')}",
        history[:plan] = invoices[invoice.invoice_id].invoice.line_items.map { |li| li.entity_id && li.entity_id.include?("service-fee") ? nil : li.description }.compact.join(", "),
        history[:invoice_id] = "1#{invoice.invoice_id}"
      elsif transaction.type == "refund"
        credit_note = transaction.linked_credit_notes[0]
        history[:delivery_date] = nil
        history[:plan] = nil
        history[:invoice_id] = "1#{credit_note.cn_reference_invoice_id}"
      end

      history
    end
end
