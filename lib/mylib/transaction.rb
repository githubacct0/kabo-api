# frozen_string_literal: true

module MyLib
  class Transaction
    class << self
      def orders(user:, subscription:, limit:, loopable:)
        invoices = {}
        transactions_list = transactions_list(user: user, limit: limit, loopable: loopable)
        invoices_list = invoices_list(user: user, limit: limit, loopable: loopable)
        invoices_list.each { |invoice| invoices[invoice.invoice.id] = invoice }

        orders = transactions_list.map { |_transaction|
          transaction_history(transaction: _transaction.transaction, subscription: subscription, invoices: invoices)
        }

        orders
      rescue StandardError => e
        Raven.capture_exception(e)
        []
      end

      def payment_method_name(transaction:)
        case transaction.payment_method
        when "paypal_express_checkout" then "PayPal"
        when "apple_pay" then "Apple Pay"
        else "Card #{transaction.masked_card_number.last(4)}"
        end
      end

      def transaction_history(transaction:, subscription:, invoices:)
        payment_method_name = payment_method_name(transaction: transaction)
        history = {
          date_timestamp: transaction.date,
          date: Time.zone.at(transaction.date).strftime("%A %b %d"),
          date_mobile: Time.zone.at(transaction.date).strftime("%a %b %d"),
          total: Money.new(transaction.amount).format,
          card: payment_method_name,
          payment_status: transaction.type == "payment" ? "Paid" : transaction.type.humanize,
        }
        items, descriptions = [], []
        if transaction.type == "payment"
          invoice = transaction.linked_invoices[0]
          schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) { |s| s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday) }
          invoice_delivery_date = schedule.next_occurrence(Time.zone.at(invoice.invoice_date)) + MyLib::Account.delivery_date_offset(subscription)
          delivery_date_text = invoice_delivery_date > Time.now ? "Delivers" : "Delivered"

          history[:delivery_date] = "#{delivery_date_text} #{(invoice_delivery_date).strftime('%b %d')}"
          invoices[invoice.invoice_id].invoice.line_items.each do |line_item|
            unless line_item.entity_id&.include?("service-fee")
              descriptions << line_item.description
              description = line_item.description
              if description&.include? "Kibble Recipe"
                recipe_name = description.split("Kibble Recipe")[0]&.strip
                items << Dog.recipe_by_name(name: recipe_name)
              elsif description&.include? "Recipe"
                recipe_name = description.split("Recipe")[0]&.strip
                items << Dog.get_recipe_details(name: recipe_name)
              end
            end
          end
          history[:plan] = descriptions.join(", ")
          history[:invoice_id] = "1#{invoice.invoice_id}"
          history[:items] = items
        elsif transaction.type == "refund"
          credit_note = transaction.linked_credit_notes[0]
          history[:delivery_date] = nil
          history[:plan] = nil
          history[:invoice_id] = "1#{credit_note.cn_reference_invoice_id}"
        end

        history
      end

      def invoices_list(user:, limit:, loopable:)
        next_offset = nil
        list = []

        # Invoices
        loop do
          query = {
            "customer_id[is]" => user.chargebee_customer_id,
            "sort_by[desc]" => "date",
            limit: limit
          }
          query[:offset] = next_offset if next_offset.present?

          result = ChargeBee::Invoice.list(query)
          list += result&.map { |invoice| invoice }

          next_offset = result.next_offset
          break if !loopable || next_offset.nil?
        end

        list
      end

      def transactions_list(user:, limit:, loopable: true)
        next_offset = nil
        list = []

        # Transactions
        loop do
          query = {
            "customer_id[is]" => user.chargebee_customer_id,
            "sort_by[desc]" => "date",
            "status[is]" => "success",
            limit: limit
          }
          query[:offset] = next_offset if next_offset.present?

          result = ChargeBee::Transaction.list(query)
          list += result&.map { |transaction| transaction }

          next_offset = result.next_offset
          break if !loopable || next_offset.nil?
        end

        list
      end
    end
  end
end
