# frozen_string_literal: true

module MyLib
  class Chargebee
    class << self
      def update_customer_and_subscription(user)
        if !user.chargebee_customer_id.blank?

          begin
            if !user.shipping_first_name.blank?
              ChargeBee::Customer.update(user.chargebee_customer_id, {
                first_name: user.shipping_first_name,
                last_name: user.shipping_last_name,
                email: user.email,
                phone: user.shipping_phone_number
              })
            end

            if !user.shipping_phone_number.blank?
              ChargeBee::Customer.update_billing_info(user.chargebee_customer_id, {
                billing_address: {
                  first_name: user.billing_first_name,
                  last_name: user.billing_last_name,
                  line1: user.billing_street_address,
                  line2: user.billing_apt_suite,
                  city: user.billing_city,
                  state: MyLib::Checkout.get_province_from_postal_code(user.billing_postal_code),
                  zip: user.billing_postal_code,
                  country: "CA",
                  phone: user.billing_phone_number,
                  email: user.email
                }
              })
            end

            if !user.billing_first_name.blank?
              ChargeBee::Customer.update_billing_info(user.chargebee_customer_id, {
                billing_address: {
                  first_name: user.billing_first_name,
                  last_name: user.billing_last_name,
                  line1: user.billing_street_address,
                  line2: user.billing_apt_suite,
                  city: user.billing_city,
                  state: MyLib::Checkout.get_province_from_postal_code(user.billing_postal_code),
                  zip: user.billing_postal_code,
                  country: "CA",
                  phone: user.billing_phone_number,
                  email: user.email
                }
              })
            end

            if !user.shipping_first_name.blank?
              list = ChargeBee::Subscription.list({
                "customer_id[is]" => user.chargebee_customer_id
              })
              list.each do |entry|
                ChargeBee::Address.update({
                  subscription_id: entry.subscription.id,
                  label: "shipping_address",
                  first_name: user.shipping_first_name,
                  last_name: user.shipping_last_name,
                  addr: user.shipping_street_address,
                  extended_addr: user.shipping_apt_suite,
                  extended_addr2: user.shipping_delivery_instructions,
                  city: user.shipping_city,
                  state_code: MyLib::Checkout.get_province_from_postal_code(user.shipping_postal_code),
                  zip: user.shipping_postal_code,
                  country: "CA",
                  email: user.email,
                  phone: user.shipping_phone_number
                })
              end
            end

            if !user.shipping_first_name.blank? && user.subscription_phase_status == "waiting_for_trial_shipment"
              # Trial user, update first order details - does not update invoice details
              list = ChargeBee::Invoice.list({
                "customer_id[is]": user.chargebee_customer_id
              })

              linked_orders = []
              list.each do |entry|
                linked_orders.push(entry.invoice.linked_orders.map { |lo| lo.id })
              end

              linked_orders.flatten.each do |linked_order|
                ChargeBee::Order.update(linked_order, {
                  shipping_address: {
                    first_name: user.shipping_first_name,
                    last_name: user.shipping_last_name,
                    line1: user.shipping_street_address,
                    line2: user.shipping_apt_suite,
                    line3: user.shipping_delivery_instructions,
                    city: user.shipping_city,
                    state_code: MyLib::Checkout.get_province_from_postal_code(user.shipping_postal_code),
                    state: MyLib::Checkout.full_province_from_code(MyLib::Checkout.get_province_from_postal_code(user.shipping_postal_code)),
                    zip: user.shipping_postal_code,
                    country: "CA",
                    email: user.email,
                    phone: user.shipping_phone_number
                  }
                })
              end
            end
          rescue StandardError => e
            Raven.capture_exception(e)
            raise e
          end

          if !user.stripe_token.blank? || !user.reference_id.blank?
            begin
              if !user.stripe_token.blank?
                ChargeBee::Card.update_card_for_customer(user.chargebee_customer_id, {
                  payment_method: {
                    type: "card",
                    tmp_token: user.stripe_token
                  }
                })
              elsif !user.reference_id.blank?
                ChargeBee::Customer.update_payment_method(user.chargebee_customer_id, {
                  payment_method: {
                    type: "paypal_express_checkout",
                    reference_id: user.reference_id
                  }
                })
              end
            rescue StandardError => e
              user.errors.add(:base, e)
              Raven.capture_exception(e)
              raise e
            end
          end

        end
      end

      def update_subscription_start_date(user, start_date)
        list = ChargeBee::Subscription.list({
          "status[is]" => "future",
          "customer_id[is]" => user.chargebee_customer_id
        })
        list.each do |entry|
          ChargeBee::Subscription.update(entry.subscription.id, {
            start_date: start_date
          })
        end

        true
      rescue StandardError => e
        Raven.capture_exception(e)

        false
      end

      def create_customer_and_invoice(user, chargebee_sku, chargebee_sku_quantity)
        if user.chargebee_customer_id.blank?
          begin
            if !user.stripe_token.blank?
              payment_method = {
                  type: "card",
                  tmp_token: user.stripe_token
              }
            else
              payment_method = {
                  type: "paypal_express_checkout",
                  reference_id: user.reference_id
              }
            end

            # create customer
            customer_result = ChargeBee::Customer.create({
              first_name: user.shipping_first_name,
              last_name: user.shipping_last_name,
              email: user.one_time_purchase_email,
              phone: user.shipping_phone_number,
              payment_method: payment_method,
              billing_address: {
                first_name: user.billing_first_name,
                last_name: user.billing_last_name,
                line1: user.billing_street_address,
                line2: user.billing_apt_suite,
                city: user.billing_city,
                state: user.billing_province,
                zip: user.billing_postal_code,
                country: "CA",
                phone: user.billing_phone_number,
                email: user.one_time_purchase_email
              },
              cf_trial_dog_name: user.trial_dog_name
            })
          rescue StandardError => e
            user.errors.add(:base, e)
            Raven.capture_exception(e)
            raise e
          end

          coupon_code = nil

          coupon_code = user.referral_code if !user.referral_code.blank?

          # create one-off invoice for customer
          invoice_result = ChargeBee::Invoice.create({
            customer_id: customer_result.customer.id,
            shipping_address: {
              first_name: user.shipping_first_name,
              last_name: user.shipping_last_name,
              line1: user.shipping_street_address,
              line2: user.shipping_apt_suite,
              line3: user.shipping_delivery_instructions,
              city: user.shipping_city,
              state_code: user.shipping_province,
              zip: user.shipping_postal_code,
              country: "CA",
              phone: user.shipping_phone_number,
              email: user.one_time_purchase_email
            },
            addons: [
              {
                id: chargebee_sku,
                quantity: chargebee_sku_quantity
              }
            ],
            coupon: coupon_code
            })

          # TODO: if invoice_result status is "payment_due", delete invoice and customer and show error due to failed transaction
          # alternatively check against linked_payments -> txn_status for "failure"
          begin
            if invoice_result.invoice.status == "payment_due" && Rails.env.production?
              mg_client = Mailgun::Client.new(Rails.configuration.mailgun_api_key)
              mb_obj = Mailgun::MessageBuilder.new
              mb_obj.from("help@kabo.co")
              mb_obj.add_recipient(:to, "vijay@kabo.co")
              mb_obj.subject("Kabo One Time Purchase - Payment Capture Failure - #{user.one_time_purchase_email}")
              mb_obj.body_text("Kabo One Time Purchase payment failed to capture for chargebee customer: #{customer_result.customer.id}")
              mg_client.send_message("mg.kabo.co", mb_obj)
            end
          rescue StandardError => e
            Raven.capture_exception(e)
          end

          user.update_columns(
            chargebee_customer_id: customer_result.customer.id,
            verified: true,
            first_checkout_at: DateTime.now
          )

          begin
            if Rails.env.production? && Rails.configuration.heroku_app_name.to_s == "kabo-app"
              LobAddressVerificationWorker.perform_async({
                shipping_street_address: user.shipping_street_address,
                shipping_apt_suite: user.shipping_apt_suite,
                shipping_city: user.shipping_city,
                shipping_province: user.shipping_province,
                shipping_postal_code: user.shipping_postal_code,
                email: user.email,
                chargebee_customer_id: user.chargebee_customer_id
              })
            end
          rescue StandardError => e
            Raven.capture_exception(e)
          end

          { customer: customer_result.customer, invoice: invoice_result.invoice }
        end
      end

      def unpause_subscription(user, dog)
        subscription_start_date = MyLib::Icecube.subscription_start_date

        if !user.stripe_token.blank? || !user.reference_id.blank?
          begin
            if !user.stripe_token.blank?
              ChargeBee::Card.update_card_for_customer(user.chargebee_customer_id, {
                payment_method: {
                  type: user.stripe_type,
                  tmp_token: user.stripe_token
                }
              })
            elsif !user.reference_id.blank?
              ChargeBee::Customer.update_payment_method(user.chargebee_customer_id, {
                payment_method: {
                  type: "paypal_express_checkout",
                  reference_id: user.reference_id
                }
              })
            end
          rescue ChargeBee::PaymentError=> ex
            AirtableWorker.perform_async(
              table_id: "appO8lrXXmebSAgMU",
              view_name: "Customers",
              record: {
                "Email": user.email,
                "Error Text": ex.message,
                "Error Code": ex.api_error_code,
                "Action": "Unpause Subscription"
              }
            )

            user.errors.add(:base, "There was a problem with your payment method, please check the details and try again")
            raise ActiveRecord::Rollback
          end
        end

        if !user.billing_first_name.blank?
          ChargeBee::Customer.update_billing_info(user.chargebee_customer_id, {
            billing_address: {
              first_name: user.billing_first_name,
              last_name: user.billing_last_name,
              line1: user.billing_street_address,
              line2: user.billing_apt_suite,
              city: user.billing_city,
              state: MyLib::Checkout.get_province_from_postal_code(user.billing_postal_code),
              zip: user.billing_postal_code,
              country: "CA",
              phone: user.billing_phone_number,
              email: user.email
            }
          })
        end

        ChargeBee::Customer.update(user.chargebee_customer_id, {
          first_name: user.shipping_first_name,
          last_name: user.shipping_last_name,
          email: user.email,
          phone: user.shipping_phone_number
        })

        ChargeBee::Subscription.resume(dog.chargebee_subscription_id, {
          resume_option: "immediately",
          charges_handling: "add_to_unbilled_charges"
        })

        begin
          ChargeBee::Subscription.change_term_end(dog.chargebee_subscription_id, {
            term_ends_at: subscription_start_date
          })
        rescue StandardError => e
          Raven.capture_exception(e)
        end

        # add addon for lower AOV customers, only if the customer has 1 dog
        subscription_param_addons = []
        if user.dogs.count == 1 && dog.kibble_portion.blank? && dog.plan_units_v2(true) < user.plan_unit_fee_limit
          subscription_param_addons.push(
            {
              id: "delivery-service-fee-#{user.how_often.split("_")[0]}-weeks"
            }
          )
        end

        # RECURRING ADDONS
        subscription_param_addons.push({
          id: "beef_#{user.chargebee_plan_interval}",
          unit_price: user.unit_price("beef_#{user.chargebee_plan_interval}"),
          quantity: dog.plan_units_v2
        }) if dog.beef_recipe

        subscription_param_addons.push({
          id: "chicken_#{user.chargebee_plan_interval}",
          unit_price: user.unit_price("chicken_#{user.chargebee_plan_interval}"),
          quantity: dog.plan_units_v2
        }) if dog.chicken_recipe

        subscription_param_addons.push({
          id: "turkey_#{user.chargebee_plan_interval}",
          unit_price: user.unit_price("turkey_#{user.chargebee_plan_interval}"),
          quantity: dog.plan_units_v2
        }) if dog.turkey_recipe

        subscription_param_addons.push({
          id: "#{dog.kibble_recipe}_kibble_#{user.chargebee_plan_interval}",
          quantity: dog.kibble_quantity_v2
        }) if !dog.kibble_recipe.blank?

        subscription_update_params = {
          plan_id: user.chargebee_plan_interval,
          addons: subscription_param_addons,
          end_of_term: true,
          replace_addon_list: true,
          cf_resume_start_date: subscription_start_date,
          shipping_address: {
            first_name: user.shipping_first_name,
            last_name: user.shipping_last_name,
            line1: user.shipping_street_address,
            line2: user.shipping_apt_suite,
            line3: user.shipping_delivery_instructions,
            city: user.shipping_city,
            state_code: MyLib::Checkout.get_province_from_postal_code(user.shipping_postal_code),
            zip: user.shipping_postal_code,
            country: "CA",
            phone: user.shipping_phone_number,
            email: user.email
          }
        }

        subscription_update_params[:coupon_ids] = [user.referral_code] if !user.referral_code.blank?

        subscription_update_result = ChargeBee::Subscription.update(dog.chargebee_subscription_id, subscription_update_params)

        # Remove unbilled charges from subscription (for out-of-term unpause)
        Chargebee::RemoveUnbilledChargesFromSubscriptionWorker.perform_async(
          subscription_id: dog.chargebee_subscription_id
        )

        subscription_update_result
      end

      def reactivate_subscription(user, dog)
        subscription_start_date = MyLib::Icecube.subscription_start_date

        if !user.stripe_token.blank? || !user.reference_id.blank?
          begin
            if !user.stripe_token.blank?
              ChargeBee::Card.update_card_for_customer(user.chargebee_customer_id, {
                payment_method: {
                  type: user.stripe_type,
                  tmp_token: user.stripe_token
                }
              })
            elsif !user.reference_id.blank?
              ChargeBee::Customer.update_payment_method(user.chargebee_customer_id, {
                payment_method: {
                  type: "paypal_express_checkout",
                  reference_id: user.reference_id
                }
              })
            end
          rescue ChargeBee::PaymentError=> ex
            AirtableWorker.perform_async(
              table_id: "appO8lrXXmebSAgMU",
              view_name: "Customers",
              record: {
                "Email": user.email,
                "Error Text": ex.message,
                "Error Code": ex.api_error_code,
                "Action": "Reactivate Subscription"
              }
            )

            user.errors.add(:base, "There was a problem with your payment method, please check the details and try again")
            raise ActiveRecord::Rollback
          end
        end

        if !user.billing_first_name.blank?
          ChargeBee::Customer.update_billing_info(user.chargebee_customer_id, {
            billing_address: {
              first_name: user.billing_first_name,
              last_name: user.billing_last_name,
              line1: user.billing_street_address,
              line2: user.billing_apt_suite,
              city: user.billing_city,
              state: MyLib::Checkout.get_province_from_postal_code(user.billing_postal_code),
              zip: user.billing_postal_code,
              country: "CA",
              phone: user.billing_phone_number,
              email: user.email
            }
          })
        end

        ChargeBee::Customer.update(user.chargebee_customer_id, {
          first_name: user.shipping_first_name,
          last_name: user.shipping_last_name,
          email: user.email,
          phone: user.shipping_phone_number
        })

        # add addon for lower AOV customers, only if the customer has 1 dog
        subscription_param_addons = []
        if user.dogs.count == 1 && dog.kibble_portion.blank? && dog.plan_units_v2(true) < user.plan_unit_fee_limit
          subscription_param_addons.push(
            {
              id: "delivery-service-fee-#{user.how_often.split("_")[0]}-weeks"
            }
          )
        end

        # RECURRING ADDONS
        subscription_param_addons.push({
          id: "beef_#{user.chargebee_plan_interval}",
          unit_price: user.unit_price("beef_#{user.chargebee_plan_interval}"),
          quantity: dog.plan_units_v2
        }) if dog.beef_recipe

        subscription_param_addons.push({
          id: "chicken_#{user.chargebee_plan_interval}",
          unit_price: user.unit_price("chicken_#{user.chargebee_plan_interval}"),
          quantity: dog.plan_units_v2
        }) if dog.chicken_recipe

        subscription_param_addons.push({
          id: "turkey_#{user.chargebee_plan_interval}",
          unit_price: user.unit_price("turkey_#{user.chargebee_plan_interval}"),
          quantity: dog.plan_units_v2
        }) if dog.turkey_recipe

        subscription_param_addons.push({
          id: "#{dog.kibble_recipe}_kibble_#{user.chargebee_plan_interval}",
          quantity: dog.kibble_quantity_v2
        }) if !dog.kibble_recipe.blank?

        subscription_update_params = {
          plan_id: user.chargebee_plan_interval,
          addons: subscription_param_addons,
          replace_addon_list: true,
          cf_resume_start_date: subscription_start_date,
          shipping_address: {
            first_name: user.shipping_first_name,
            last_name: user.shipping_last_name,
            line1: user.shipping_street_address,
            line2: user.shipping_apt_suite,
            line3: user.shipping_delivery_instructions,
            city: user.shipping_city,
            state_code: MyLib::Checkout.get_province_from_postal_code(user.shipping_postal_code),
            zip: user.shipping_postal_code,
            country: "CA",
            phone: user.shipping_phone_number,
            email: user.email
          }
        }

        subscription_update_params[:coupon_ids] = [user.referral_code] if !user.referral_code.blank?

        begin
          subscription_update_result = ChargeBee::Subscription.update(dog.chargebee_subscription_id, subscription_update_params)

          ChargeBee::Subscription.reactivate(dog.chargebee_subscription_id) if subscription_update_result.subscription.status != "active"
        rescue ChargeBee::PaymentError=> ex
          AirtableWorker.perform_async(
            table_id: "appO8lrXXmebSAgMU",
            view_name: "Customers",
            record: {
              "Email": user.email,
              "Error Text": ex.message,
              "Error Code": ex.api_error_code,
              "Action": "Reactivate Subscription"
            }
          )

          user.errors.add(:base, "There was a problem with your payment method, please check the details and try again")
          raise ActiveRecord::Rollback
        end

        # Future billing date after current term
        future_schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        future_billing_date = future_schedule.next_occurrences(2, Time.zone.at(subscription_start_date))[1].utc.to_i

        ChargeBee::Subscription.change_term_end(dog.chargebee_subscription_id, {
          term_ends_at: future_billing_date
        })

        subscription_update_result
      end

      # Update subscription
      def update_subscription(
        subscription_status:,
        has_scheduled_changes:,
        dog_chargebee_subscription_id:,
        chargebee_plan_interval:,
        addons:,
        apply_coupon_statuses:
      )
        existing_coupon_codes = []
        if has_scheduled_changes
          scheduled_changes = ChargeBee::Subscription.retrieve_with_scheduled_changes(dog_chargebee_subscription_id).subscription
          scheduled_changes.coupons && existing_coupon_codes.push(scheduled_changes.coupons[0].coupon_id)
          ChargeBee::Subscription.remove_scheduled_changes(dog_chargebee_subscription_id)
        end

        update_params = {
          plan_id: chargebee_plan_interval,
          addons: addons,
          replace_addon_list: true
        }
        update_params[:coupon_ids] = existing_coupon_codes if apply_coupon_statuses.include? subscription_status
        subscription_status == "active" && update_params[:end_of_term] = true

        ChargeBee::Subscription.update(dog_chargebee_subscription_id, update_params)
      end
    end
  end
end
