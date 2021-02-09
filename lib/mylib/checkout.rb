# frozen_string_literal: true

module MyLib
  class Checkout
    class << self
      def estimate_v2(user, dog, original_referral_code = nil, saved_referral_code = nil, postal_code = nil, is_temp_user = false)
        dogs = is_temp_user ? user.temp_dogs : user.dogs
        user_chargebee_plan_interval = user.chargebee_plan_interval
        is_temp_user = is_temp_user || !user.verified
        referral_code_check = MyLib::Referral.check_code(original_referral_code)
        request_referral_code_check = referral_code_check

        saved_referral_code_check = MyLib::Referral.check_code(saved_referral_code)

        if !referral_code_check && saved_referral_code_check && saved_referral_code.present?
          referral_code = saved_referral_code
          referral_code_check = saved_referral_code_check
        else
          referral_code = original_referral_code
        end

        if referral_code.nil? && !referral_code_check
          referral_code = "40off"
          referral_code_check = "40%"
        end

        referral_codes = []
        referral_codes.push(referral_code) if is_temp_user || original_referral_code.present? && referral_code_check

        if dogs.map { |d| d.turkey_recipe }.include?(true) || dogs.map { |d| ["turkey+salmon", "duck"].include?(d.kibble_recipe) }.include?(true)
          # Delay cycle for new recipes
          start_date = "2020-11-20 12:00:00"
        else
          start_date = "2020-01-03 12:00:00"
        end
        subscription_start_date = MyLib::Icecube.subscription_start_date(start_date)

        subscription_params = {
          plan_id: user_chargebee_plan_interval,
          start_date: subscription_start_date
        }

        address_for_taxes = {}

        if postal_code.present?
          address_for_taxes = {
            state_code: get_province_from_postal_code(postal_code), # In format of ON, BC, etc.
            country: "CA"
          }
        end

        subscription_addons = []

        # For smaller dogs fee
        if dogs.where.not(meal_type: "food_restriction").count == 1 && dog.plan_units < user.plan_unit_fee_limit
          subscription_addons.push(
            {
              id: "delivery-service-fee-#{user.how_often.split("_")[0]}-weeks"
            }
          )
        end

        subscription_addons.push({
          id: "beef_#{user_chargebee_plan_interval}",
          quantity: dog.plan_units_v2,
          unit_price: user.unit_price("beef_#{user_chargebee_plan_interval}")
        }) if dog.beef_recipe

        subscription_addons.push({
          id: "chicken_#{user_chargebee_plan_interval}",
          quantity: dog.plan_units_v2,
          unit_price: user.unit_price("chicken_#{user_chargebee_plan_interval}")
        }) if dog.chicken_recipe

        subscription_addons.push({
          id: "turkey_#{user_chargebee_plan_interval}",
          quantity: dog.plan_units_v2,
          unit_price: user.unit_price("turkey_#{user_chargebee_plan_interval}")
        }) if dog.turkey_recipe

        subscription_addons.push({
          id: "#{dog.kibble_recipe}_kibble_#{user_chargebee_plan_interval}",
          quantity: dog.kibble_quantity_v2
        }) if !dog.kibble_recipe.blank?

        result = ChargeBee::Estimate.create_subscription({
          subscription: subscription_params,
          coupon_ids: referral_codes,
          billing_address: address_for_taxes,
          addons: subscription_addons
        })
        invoice_estimate = result.estimate.next_invoice_estimate

        if dogs.count > 1 && is_temp_user
          total_price_estimate = 0
          dogs.each do |multiple_dog|
            multiple_subscription_params = {
              plan_id: user_chargebee_plan_interval,
              start_date: subscription_start_date
            }

            multiple_dog_subscription_addons = []

            multiple_dog_subscription_addons.push({
              id: "beef_#{user_chargebee_plan_interval}",
              quantity: multiple_dog.plan_units_v2,
              unit_price: user.unit_price("beef_#{user_chargebee_plan_interval}")
            }) if multiple_dog.beef_recipe

            multiple_dog_subscription_addons.push({
              id: "chicken_#{user_chargebee_plan_interval}",
              quantity: multiple_dog.plan_units_v2,
              unit_price: user.unit_price("chicken_#{user_chargebee_plan_interval}")
            }) if multiple_dog.chicken_recipe

            multiple_dog_subscription_addons.push({
              id: "turkey_#{user_chargebee_plan_interval}",
              quantity: multiple_dog.plan_units_v2,
              unit_price: user.unit_price("turkey_#{user_chargebee_plan_interval}")
            }) if multiple_dog.turkey_recipe

            multiple_dog_subscription_addons.push({
              id: "#{multiple_dog.kibble_recipe}_kibble_#{user_chargebee_plan_interval}",
              quantity: multiple_dog.kibble_quantity_v2
            }) if !multiple_dog.kibble_recipe.blank?

            multiple_result = ChargeBee::Estimate.create_subscription({
              subscription: multiple_subscription_params,
              coupon_ids: referral_codes,
              billing_address: address_for_taxes,
              addons: multiple_dog_subscription_addons
            })
            total_invoice_estimate = multiple_result.estimate.next_invoice_estimate
            total_price_estimate += total_invoice_estimate.total
          end
        else
          total_price_estimate = invoice_estimate.total
        end

        purchase_by_date = (Time.now + 2.days).strftime("%b %e, %Y")
        purchase_by_date = Time.zone.at(subscription_start_date).strftime("%b %e, %Y") if Time.now + 2.days > Time.zone.at(subscription_start_date)

        default_delivery_date = subscription_start_date + 7.days
        if postal_code.present?
          default_delivery_date = subscription_start_date + MyLib::Account.delivery_date_offset_by_postal_code(postal_code)

          # Manual override for AB/BC orders (Nov 11)
          default_delivery_date = subscription_start_date + 4.days if ["AB", "BC"].include?(get_province_from_postal_code(postal_code))
        end

        productReturn = {
          topperAvailable: dog.topper_available,
          productDescription: [
            "Arrives #{Time.zone.at(default_delivery_date).strftime("%b %e, %Y")} if you purchase by #{purchase_by_date}",
            "#{Time.zone.at(default_delivery_date).utc.strftime("%d/%m/%y")}"
          ],
          priceDetails: [
            { title: "Shipping", details: "FREE!", margin_bottom: 2 },
            { title: "Tax #{ "(" + invoice_estimate.taxes.map { |t| t.name }.join(' & ') + ")" if invoice_estimate.taxes.any?}", details: (invoice_estimate.taxes.empty? ? "--" : Money.new(invoice_estimate.taxes.reduce(0) { |sum, tax| sum + tax.amount }).format), margin_bottom: 2 }
          ],
          priceTotal: { title: "Total Due", details: Money.new(total_price_estimate).format },
          referral: request_referral_code_check ? "'#{referral_code}' used. #{referral_code_check} discount applied!" : "Sorry, your coupon code is invalid",
          mealplanInfo: []
        }

        productReturn[:mealplanInfo].push("Freshly Cooked: #{dog.readable_cooked_recipes}") if dog.readable_cooked_recipes
        productReturn[:mealplanInfo].push("Fresh Kibble: #{dog.readable_kibble_recipe}") if dog.readable_kibble_recipe
        productReturn[:mealplanInfo].push("Portion: #{dog.readable_portion_v2}")  if dog.readable_portion_v2
        productReturn[:mealplanInfo].push("Amount: #{user_chargebee_plan_interval[0]} weeks worth of food")

        productReturn[:priceDetails].insert(0, {
          title: "First order discount (#{referral_code_check})",
          details: "-" + Money.new(invoice_estimate.discounts[0].amount).format,
          margin_bottom: 2
        }) if is_temp_user

        productReturn[:priceDetails].insert(0, {
          title: "Order discount (#{referral_code_check})",
          details: "-" + Money.new(invoice_estimate.discounts[0].amount).format,
          margin_bottom: 2
        }) if !is_temp_user && referral_codes.any?

        productReturn[:priceDetails].insert(0, {
          title: "Fresh #{dog.kibble_recipe.sub("+", " & ")} kibble",
          details: "#{Money.new(invoice_estimate.line_items.select { |li| li.entity_id == "#{dog.kibble_recipe}_kibble_#{user_chargebee_plan_interval}" }[0].amount).format}",
          margin_bottom: 6
        }) if dog.kibble_recipe.present?

        productReturn[:priceDetails].insert(0, {
          title: "Hearty Turkey",
          details: "#{Money.new(invoice_estimate.line_items.select { |li| li.entity_id == "turkey_#{user_chargebee_plan_interval}" }[0].amount).format}",
          margin_bottom: 6
        }) if dog.turkey_recipe

        productReturn[:priceDetails].insert(0, {
          title: "Savoury Beef",
          details: "#{Money.new(invoice_estimate.line_items.select { |li| li.entity_id == "beef_#{user_chargebee_plan_interval}" }[0].amount).format}",
          margin_bottom: 6
        }) if dog.beef_recipe

        productReturn[:priceDetails].insert(0, {
          title: "Tender Chicken",
          details: "#{Money.new(invoice_estimate.line_items.select { |li| li.entity_id == "chicken_#{user_chargebee_plan_interval}" }[0].amount).format}",
          margin_bottom: 6
        }) if dog.chicken_recipe

        productReturn[:priceDetails].push({
          title: "<span style='font-weight:700;'>#{dog.name}'s Total</span>",
          details: "<span style='font-weight:700;'>#{Money.new(invoice_estimate.total).format}</span>"
        }) if dogs.where.not(meal_type: "food_restriction").count > 1

        productReturn
      end

      # TAG: DO NOT USE
      def estimate(user, dog, referral_code = "40off", referral_code_from_cookie = nil, postal_code = nil)
        referral_code_check = MyLib::Referral.check_code(referral_code)

        request_referral_code_check = referral_code_check

        referral_code_from_cookie_check = MyLib::Referral.check_code(referral_code_from_cookie)

        if !referral_code_check && referral_code_from_cookie_check && !referral_code_from_cookie.blank?
          referral_code = referral_code_from_cookie
          referral_code_check = referral_code_from_cookie_check
        end

        if referral_code.blank? || !referral_code_check
          referral_code = "40off"
          referral_code_check = "40%"
        end

        schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        subscription_start_date = schedule.next_occurrence.utc.to_i

        subscription_params = {
          plan_id: dog.meal_type + "_" + user.chargebee_plan_interval,
          plan_quantity: dog.plan_units,
          plan_unit_price: user.unit_price(dog.meal_type + "_" + user.chargebee_plan_interval),
          start_date: subscription_start_date
        }

        address_for_taxes = {}

        if !postal_code.nil?
          address_for_taxes = {
            state_code: get_province_from_postal_code(postal_code), # In format of ON, BC, etc.
            country: "CA"
          }
        end

        subscription_addons = []

        # For smaller dogs fee
        small_dog_fee_applied = false
        if user.dogs.where.not(meal_type: "food_restriction").count == 1 && dog.plan_units < user.plan_unit_fee_limit
          subscription_addons.push(
            {
              id: "delivery-service-fee-#{user.how_often.split("_")[0]}-weeks"
            }
          )
          small_dog_fee_applied = true
        end

        kibble_sku = "chicken_5lb_kibble_#{user.chargebee_plan_interval}"

        if !dog.kibble_type.blank?
          subscription_addons.push(
            {
              id: kibble_sku,
              quantity: dog.kibble_quantity
            }
          )
        end

        result = ChargeBee::Estimate.create_subscription({
          subscription: subscription_params,
          coupon_ids: [referral_code],
          billing_address: address_for_taxes,
          addons: subscription_addons
        })
        @invoice_estimate = result.estimate.next_invoice_estimate

        kibble_line_item = @invoice_estimate.line_items.select { |li| li.entity_id == kibble_sku }[0]

        fresh_food_line_item_amount = @invoice_estimate.line_items.select { |li| li.entity_id == (dog.meal_type + "_" + user.chargebee_plan_interval) }[0].amount

        # if small dog fee
        if small_dog_fee_applied
          fresh_food_line_item_amount += @invoice_estimate.line_items.select { |li| li.entity_id == "delivery-service-fee-#{user.how_often.split("_")[0]}-weeks" }[0].amount
        end

        if user.dogs.where.not(meal_type: "food_restriction").count > 1
          total_price_estimate = 0
          user.dogs.where.not(meal_type: "food_restriction").each do |multiple_dog|
            mt = multiple_dog.meal_type
            pu = multiple_dog.plan_units

            if dog.id == multiple_dog.id
              mt = dog.meal_type
              pu = dog.plan_units
            end

            multiple_subscription_params = {
              plan_id: mt + "_" + user.chargebee_plan_interval,
              plan_quantity: pu,
              plan_unit_price: user.unit_price(mt + "_" + user.chargebee_plan_interval),
              start_date: subscription_start_date
            }

            # multiple_default_address = {
            #   :state_code => "ON",
            #   :country => 'CA'
            # }

            multiple_dog_subscription_addons = []

            if !multiple_dog.kibble_type.blank?
              multiple_dog_subscription_addons.push(
                {
                  id: kibble_sku,
                  quantity: multiple_dog.kibble_quantity
                }
              )
            end

            multiple_result = ChargeBee::Estimate.create_subscription({
              subscription: multiple_subscription_params,
              coupon_ids: [referral_code],
              billing_address: address_for_taxes,
              addons: multiple_dog_subscription_addons
            })
            total_invoice_estimate = multiple_result.estimate.next_invoice_estimate
            total_price_estimate += total_invoice_estimate.total
          end
        else
          total_price_estimate = @invoice_estimate.total
        end

        purchase_by_date = (Time.now + 2.days).strftime("%b %e, %Y")
        if Time.now + 2.days > (Time.zone.at(subscription_start_date))
          purchase_by_date = Time.zone.at(subscription_start_date).strftime("%b %e, %Y")
        end

        default_delivery_date = subscription_start_date + 7.days
        if !postal_code.nil?
          default_delivery_date = subscription_start_date + MyLib::Account.delivery_date_offset_by_postal_code(postal_code)
        end

        productReturn = {
          topperAvailable: dog.topper_available,
          productDescription: [
            "<span class='checkout-delivery-date' style='font-weight: 400;'>Arrives #{Time.zone.at(default_delivery_date).strftime("%b %e, %Y")} if you purchase by #{purchase_by_date}</span>",
            "<span class='checkout-delivery-date-value' style='display: none;'>#{Time.zone.at(default_delivery_date).utc.strftime("%d/%m/%y")}</span>"
          ],
          priceDetails: [
            { title: "#{user.chargebee_plan_interval.split("_")[0]} weeks of cooked food (#{dog.meal_type.split('_')[0]}% portion)", details: "#{Money.new(fresh_food_line_item_amount).format}", margin_bottom: 6 },
            { title: "First order discount (#{referral_code_check})", details: "-" + Money.new(@invoice_estimate.discounts[0].amount).format, margin_bottom: 2 },
            { title: "Shipping", details: "FREE!", margin_bottom: 2 },
            { title: "Tax #{ "(" + @invoice_estimate.taxes.map { |t| t.name }.join(' & ') + ")" if !@invoice_estimate.taxes.empty?}", details: (@invoice_estimate.taxes.empty? ? "--" : Money.new(@invoice_estimate.taxes.reduce(0) { |sum, tax| sum + tax.amount }).format), margin_bottom: 2 }
          ],
          priceTotal: { title: "Total Due", details: Money.new(total_price_estimate).format },
          referral: request_referral_code_check ? "'#{referral_code}' used. #{referral_code_check} discount applied!" : "Invalid code, but don't worry your #{referral_code_from_cookie_check ? referral_code_from_cookie_check : "40%"} discount is still applied!"
        }

        productReturn[:priceDetails].insert(1, {
          title: "#{kibble_line_item.quantity} #{'bag'.pluralize(kibble_line_item.quantity)} of fresh chicken kibble (75% portion)",
          details: Money.new(kibble_line_item.amount).format,
          removable: true,
          margin_bottom: 6
        }) if !dog.kibble_type.blank?

        productReturn[:priceDetails].insert(1, {
          title: "Add fresh chicken kibble (75% portion)",
          addable: true,
          margin_bottom: 6
        }) if dog.kibble_type.blank? && dog.meal_type.split("_")[0] == "25"

        productReturn[:priceDetails].push({
          title: "<span style='font-weight:700;'>#{dog.name}'s Total</span>",
          details: "<span style='font-weight:700;'>#{Money.new(@invoice_estimate.total).format}</span>"
        }) if user.dogs.where.not(meal_type: "food_restriction").count > 1

        productReturn
      end

      def estimate_single_product(user, quantity = 1, referral_code = nil, referral_code_from_cookie = nil, postal_code = nil)
        referral_code_check = MyLib::Referral.check_code(referral_code)

        request_referral_code_check = referral_code_check

        # referral_code_from_cookie_check = MyLib::Referral.check_code(referral_code_from_cookie)

        # if !referral_code_check && referral_code_from_cookie_check && !referral_code_from_cookie.blank?
        #   referral_code = referral_code_from_cookie
        #   referral_code_check = referral_code_from_cookie_check
        # end

        if user.one_time_purchase_sku.include?("kibble")
          schedule = IceCube::Schedule.new(Time.zone.parse("2020-07-16 12:00:00")) do |s|
            s.add_recurrence_rule IceCube::Rule.weekly(1).day(:thursday)
          end
        else
          schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
            s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
          end
        end

        subscription_start_date = schedule.next_occurrence.utc.to_i

        subscription_params = {
          plan_id: "one-time-purchase",
          start_date: subscription_start_date
        }

        address_for_taxes = {}

        if !postal_code.nil?
          address_for_taxes = {
            state_code: get_province_from_postal_code(postal_code), # In format of ON, BC, etc.
            country: "CA"
          }
        end

        quantity = 1 if quantity.blank?

        subscription_event_based_addons = []

        subscription_event_based_addons.push(
          {
            id: user.one_time_purchase_sku,
            quantity: quantity,
            on_event: "subscription_creation",
            charge_once: true,
            charge_on: "on_event"
          }
        )

        coupon_ids = []

        coupon_ids = [referral_code] if !referral_code.blank? && referral_code_check

        result = ChargeBee::Estimate.create_subscription({
          subscription: subscription_params,
          coupon_ids: coupon_ids,
          billing_address: address_for_taxes,
          event_based_addons: subscription_event_based_addons
        })

        @invoice_estimate = result.estimate.invoice_estimate

        total_price_estimate = @invoice_estimate.total

        purchase_by_date = (Time.now + 2.days).strftime("%b %e, %Y")
        if Time.now + 2.days > (Time.zone.at(subscription_start_date))
          purchase_by_date = Time.zone.at(subscription_start_date).strftime("%b %e, %Y")
        end

        kibble_delivery_offset = 0.days
        if user.one_time_purchase_sku.include?("kibble")
          kibble_delivery_offset = 1.day
        end

        default_delivery_date = subscription_start_date + 7.days + kibble_delivery_offset
        if !postal_code.nil?
          if user.one_time_purchase_sku.include?("kibble")
            default_delivery_date = subscription_start_date + MyLib::Account.delivery_date_for_kibble_offset_by_postal_code(postal_code) + 1.day
          else
            default_delivery_date = subscription_start_date + MyLib::Account.delivery_date_offset_by_postal_code(postal_code)
          end
        end

        addon_result = ChargeBee::Addon.retrieve(user.one_time_purchase_sku)

        productReturn = {
          productDetails: {
            title: (addon_result.addon.meta_data.nil? || addon_result.addon.meta_data[:"product-title"].blank?) ? @invoice_estimate.line_items[0].description : addon_result.addon.meta_data[:"product-title"]
          },
          productDescription: [
            "<span class='checkout-delivery-date' style='font-weight: 400;'>Arrives #{Time.zone.at(default_delivery_date).strftime("%b %e, %Y")} if you purchase by #{purchase_by_date}</span>",
            "<span class='checkout-delivery-date-value' style='display: none;'>#{Time.zone.at(default_delivery_date).utc.strftime("%d/%m/%y")}</span>"
          ],
          priceDetails: [
            { title: "#{@invoice_estimate.line_items[0].description} (x#{quantity})", details: "#{Money.new(@invoice_estimate.line_items[0].amount).format}" },
            { title: "Shipping", details: "FREE!" },
            { title: "Tax #{ "(" + @invoice_estimate.taxes.map { |t| t.name }.join(' & ') + ")" if !@invoice_estimate.taxes.empty?}", details: (@invoice_estimate.taxes.empty? ? "--" : Money.new(@invoice_estimate.taxes.reduce(0) { |sum, tax| sum + tax.amount }).format) }
          ],
          priceTotal: { title: "Total Due", details: Money.new(total_price_estimate).format },
          referral: request_referral_code_check ? "'#{referral_code}' used. #{referral_code_check} discount applied!" : "Invalid code"
        }

        productReturn[:priceDetails].insert(1, { title: "Discount (#{referral_code_check})", details: "-" + Money.new(@invoice_estimate.discounts[0].amount).format }) if @invoice_estimate.discounts

        productReturn
      end

      def estimate_trial
        schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        subscription_start_date = schedule.next_occurrence.utc.to_i

        subscription_params = {
          plan_id: "25_beef_2_weeks",
          plan_quantity: 16,
          start_date: Time.now.utc.to_i,
          plan_unit_price: 0
        }

        default_address = {
          state_code: "ON",
          country: "CA"
        }

        result = ChargeBee::Estimate.create_subscription({
          subscription: subscription_params,
          billing_address: default_address,
          event_based_addons: [
            {
              id: "free-sample-shipping",
              on_event: "subscription_creation",
              charge_once: true,
              charge_on: "on_event"
            }
          ]
        })

        {
          productDescription: [
            "1 Savoury Beef Recipe",
            "Free",
            "<span class='checkout-delivery-date'>Delivers #{Time.zone.at(subscription_start_date + 7.days).utc.strftime("%b %e, %Y")}</span>",
            "<span class='checkout-delivery-date-value' style='display: none;'>#{Time.zone.at(subscription_start_date + 7.days).utc.strftime("%d/%m/%y")}</span>"
          ],
          priceDetails: [
            { title: "1 lb Kabo Meal", details: "Free" },
            { title: "Shipping", details: Money.new(result.estimate.invoice_estimate.sub_total).format },
            { title: "Tax", details: Money.new(result.estimate.invoice_estimate.taxes[0].amount).format }
          ],
          priceTotal: { title: "Total Due", details: Money.new(result.estimate.invoice_estimate.total).format }
        }
      end

      def serviceable_postal_code(postal_code)
        postal_code = postal_code.delete(" ")

        return false if postal_code.blank? || postal_code.length > 6

        return true if ServiceablePostalCode.where(postal_code: postal_code[0..2].upcase, fsa: true)
          .or(ServiceablePostalCode.where(postal_code: postal_code[0..4].upcase, loomis: true))
          .or(ServiceablePostalCode.where(postal_code: postal_code[0..5].upcase, fedex: true)).first

        begin
          if Rails.env.production? && (Rails.configuration.heroku_app_name == "kabo-app")
            AirtableWorker.perform_async(
              table_id: "appuRzASkhkHMbt6Z",
              view_name: "Postal Codes",
              record: {
                "Postal Code": postal_code
              }
            )
          end
        rescue StandardError => e
          Raven.capture_exception(e)
        end

        false
      end

      def get_province_from_postal_code(postal_code)
        postal_code = postal_code.delete(" ")

        return "" if postal_code.blank? || postal_code.length > 6

        return ServiceablePostalCode.where(postal_code: postal_code[0..2].upcase, fsa: true).first.try(:province)

        return ServiceablePostalCode.where(postal_code: postal_code[0..4].upcase, loomis: true).first.try(:province)

        return ServiceablePostalCode.where(postal_code: postal_code[0..5].upcase, fedex: true).first.try(:province)

        ""
      end

      def full_province_from_code(province_code)
        case province_code
        when "NL"
          "Newfoundland and Labrador"
        when "PE"
          "Prince Edward Island"
        when "NS"
          "Nova Scotia"
        when "NB"
          "New Brunswick"
        when "QC"
          "Quebec"
        when "ON"
          "Ontario"
        when "MB"
          "Manitoba"
        when "SK"
          "Saskatchewan"
        when "AB"
          "Alberta"
        when "BC"
          "British Columbia"
        end
      end

      def ace_postal_code(postal_code)
        return false if postal_code.blank?

        serviceable_outward_codes = [
          "M6L", "M8V", "M9A", "M9N", "M2L", "M4B", "M4K", "M4S", "M5A", "M5J", "M5R",
          "M6A", "M6J", "L4W", "L5C", "L5L", "L3T", "M2N", "M3M", "L4T", "L6R", "L6Y",
          "L3P", "M1T", "M1C", "M1L", "L4H", "L4B", "M6M", "M8W", "M9B", "M9P", "M2P",
          "M4C", "M4L", "M4T", "M5B", "M5K", "M5S", "M6B", "M6K", "L4X", "L5E", "L5M",
          "L4J", "M2R", "M3N", "L4V", "L6S", "L6Z", "L3R", "M1V", "M1E", "M1M", "L4K",
          "L4C", "M6N", "M8X", "M9C", "M9R", "M3A", "M4E", "M4M", "M4V", "M5C", "M5L",
          "M5T", "M6C", "M7A", "L4Y", "L5G", "L5N", "M2H", "M3H", "L5P", "L6T", "L7A",
          "L3S", "M1W", "M1G", "M1N", "L4L", "L4E", "M6P", "M8Y", "M9L", "M9V", "M3B",
          "M4G", "M4N", "M4W", "M5E", "M5M", "M5V", "M6E", "L4Z", "L5H", "L5R", "M2J",
          "M3J", "L5S", "L6V", "L6G", "M1X", "M1H", "M1P", "L6A", "L4S", "M6R", "M8Z",
          "M9M", "M9W", "M3C", "M4H", "M4P", "M4X", "M5G", "M5N", "M5W", "M6G", "L5A",
          "L5J", "L5V", "M2K", "M3K", "L5T", "L6W", "M1B", "M1J", "M1R", "L6C", "M6S",
          "M4A", "M4J", "M4R", "M4Y", "M5H", "M5P", "M5X", "M6H", "L5B", "L5K", "M2M",
          "M3L", "L5W", "L6X", "M1S", "M1K", "L6H", "L6J", "L6K", "L6L", "L6M", "L7L",
          "L7M", "L7N", "L7P", "L7R", "L7S", "L7T", "L3Y", "L3X", "L4G", "L1V", "L1W",
          "L1S", "L1Z", "L8H", "L8K", "L8L", "L8M", "L8N", "L8P", "L8R", "L8S", "L8T",
          "L8V", "L8W", "L9A", "L9B", "L9C", "L9T", "L1M", "L1N", "L1P", "L1R", "L1J",
          "L1H", "L1G", "L1K", "L1L", "L7J", "L6B", "L6E", "L7C", "L7E", "N1R", "N1T",
          "N1P", "N1S", "N3C", "N3E", "N3H", "N2P", "N2R", "N2K", "N2L", "N2T", "N2J",
          "N2V", "N1C", "N1H", "N1G", "N1L", "N1K", "N1E", "N2E", "N2C", "N2A", "N2B",
          "N2N", "N2M", "N2G", "N2H", "L9H"
        ]

        return true if serviceable_outward_codes.include?(postal_code[0..2].upcase)

        false
      end
    end
  end
end
