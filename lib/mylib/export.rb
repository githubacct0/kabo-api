# frozen_string_literal: true

require "csv"

module MyLib
  class Export
    class << self
      # Translated from sanitizeQuantity in Quantity.js within GAS-Fulfill-Tool library
      def sanitizeQuantity(rawSize, rawFrq)
        min = 18
        max = 32
        size = (rawSize < min) ? (rawSize*2) : ((rawSize > max) ? (rawSize/2) : rawSize)
        size = (size%2) ? size : size+1 # using ! returns false, different than JS version of function
        size = 32 if size == 30 # we don't have 30 oz packs
        count = (rawSize < min) ? (rawFrq/2) : ((rawSize>max) ? rawFrq*2 : rawFrq)
        ppd = (rawSize < min)? 0.5 : ((rawSize>max) ? 2 : 1)
        [size, count, ppd]
      end

      # Combined production + shipping export
      def orders_for_production_and_shipping(query_from = nil, query_to = nil)
        current_schedule = IceCube::Schedule.new(Time.zone.parse("2019-03-29 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        previous_periods = current_schedule.previous_occurrences(2, Time.zone.now)

        order_cutoff_date = Time.zone.now

        if query_from.blank?
          query_from = previous_periods[0].utc.to_i
        end

        if query_to.blank?
          query_to = order_cutoff_date.utc.to_i
        end

        order_list_offset = nil
        subscription_list_offset = nil
        comments_list_offset = nil
        all_orders_list = []
        all_subscriptions = {}
        all_customers = {}
        all_comments = []

        loop do
          subscription_list_query = {
            limit: 100
          }

          if subscription_list_offset
            subscription_list_query[:offset] = subscription_list_offset
          end

          current_query_list = ChargeBee::Subscription.list(subscription_list_query)

          current_query_list.each do |cql|
            all_subscriptions[cql.subscription.id] = cql.subscription
            all_customers[cql.customer.id] = cql.customer
          end

          subscription_list_offset = current_query_list.next_offset
          break if subscription_list_offset.nil?
        end

        loop do
          order_list_query = {
            "status[in]" => ["queued", "delivered", "awaiting_shipment"],
            "sort_by[asc]" => "created_at",
            "order_date[between]" => [query_from, query_to],
            "subscription_id[is_not]" => "null", # Skipping non-subscription orders
            limit: 100
          }

          if order_list_offset
            order_list_query[:offset] = order_list_offset
          end

          current_query_list = ChargeBee::Order.list(order_list_query)

          current_query_list.each do |list_item|
            all_orders_list.push(list_item.order)
          end

          order_list_offset = current_query_list.next_offset
          break if order_list_offset.nil?
        end

        # Get subscription comments
        loop do
          comments_list_query = {
            :limit => 100,
            "sort_by[asc]" => "created_at",
          }

          if comments_list_offset
            comments_list_query[:offset] = comments_list_offset
          end

          current_query_list = ChargeBee::Comment.list(comments_list_query)

          current_query_list.each do |list_item|
            all_comments.push(list_item.comment)
          end

          comments_list_offset = current_query_list.next_offset
          break if comments_list_offset.nil?
        end

        orders_to_ship = []

        active_status_options = ["future", "active"]

        order_schedule = IceCube::Schedule.new(Time.zone.parse("2019-03-29 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        required_attributes = [
          "dogs.chargebee_subscription_id",
          "users.chargebee_customer_id",
          "dogs.id",
          "users.id",
          "users.email",
          "dogs.food_restriction_custom",
          "dogs.name",
          "dogs.cooked_portion"
        ]
        raw_database_records = Dog.joins(:user).pluck(*required_attributes)
        database_records = {}
        database_records_no_subscription = {}
        raw_database_records.each do |record|
          if subscription_id = record.shift
            database_records[subscription_id] = {
              chargebee_customer_id: record.shift,
              dog_id: record.shift,
              user_id: record.shift,
              email: record.shift,
              food_restriction_custom: record.shift,
              dog_name: record.shift,
              cooked_portion: record.shift
            }
          elsif customer_id = record.shift
            database_records_no_subscription[customer_id] = {
              dog_id: record.shift,
              user_id: record.shift,
              email: record.shift,
              food_restriction_custom: record.shift,
              dog_name: record.shift
            }
          end
        end

        all_orders_list.each do |order|
          food_restriction_custom = ""
          first_order = ""
          dog_count = "N/A"
          combined_sku = []
          combined_plan_units = 0
          subscription_result = ""
          customer_result = ""
          order.order_line_items.each do |order_line_item|
            plan_name = order_line_item.entity_id
            box_ice_weight_lbs = 1
            subscription_status = ""
            subscription_comments = []
            line_item_name = nil

            if subscription_id = order.try(:subscription_id)
              subscription_result = all_subscriptions[subscription_id]
              subscription_status = subscription_result.status

              customer_result = all_customers[order.customer_id]

              # Skip if order is not an active customer and already shipped
              next if !active_status_options.include?(subscription_status) && order.status == "delivered"

              subscription_comments = all_comments.select do |comment|
                comment.entity_type == "subscription" && comment.entity_id == subscription_id
              end
              subscription_comments.map! { |comment| comment.notes }
            end

            # Skip if order is from 2 periods ago and not 4_weeks
            next if Time.zone.at(order.created_at) >= previous_periods[0] && Time.zone.at(order.created_at) <= previous_periods[0].change({ min: 10 }) && subscription_status == "active" && !plan_name.include?("4_weeks")

            # Purpose: Skip 4_week orders
            # Skip next if order is between 2 periods ago + 1 min to 1 period ago + 1 min and not 2_weeks
            # Need to add a minute to account for delay in processing orders
            # Adding minute to 2 periods ago to avoid automatically processed orders on that day
            # next if Time.zone.at(order.created_at) > previous_periods[0].change({min: 1}) && Time.zone.at(order.created_at) < previous_periods[1].change({min: 1}) && !plan_name.include?("2_weeks")
            # next if Time.zone.at(order.created_at) >= previous_periods[1] && Time.zone.at(order.created_at) <= previous_periods[1].change({min: 10}) && subscription_status == "active" && !plan_name.include?("2_weeks")

            if subscription_result
              dog_name = subscription_result.cf_dog_name
              human_name = "#{order.shipping_address.first_name} #{order.shipping_address.last_name}"
              email = (order.shipping_address.email || customer_result.email)

              dog_record = database_records[order.try(:subscription_id)]
              dog_count = User.find_by(chargebee_customer_id: order.customer_id).try(:dogs).try(:count)
              if !dog_record.blank?
                escaped_food_restriction_custom = %("#{dog_record[:food_restriction_custom]}")
                food_restriction_custom = "#{escaped_food_restriction_custom}"
              else
                user_record = database_records_no_subscription[order.try(:customer_id)]
                if !user_record.blank?
                  escaped_food_restriction_custom = %("#{user_record[:food_restriction_custom]}")
                  food_restriction_custom = "#{escaped_food_restriction_custom}"
                end
              end

              # Check to see if order is within first interval (first order)
              first_subscription_schedule_renewal = order_schedule.next_occurrence(Time.zone.at(subscription_result.created_at))
              if Time.zone.at(order.created_at) < first_subscription_schedule_renewal
                first_order = "YES"
              else
                first_order = "NO"
              end

            else
              human_name = "#{order.shipping_address.try(:first_name)} #{order.shipping_address.try(:last_name)}"
              trial_user = User.where(chargebee_customer_id: order.customer_id)
                              .select(:email, :trial_dog_name).first
              email = trial_user.try(:email)
              dog_name = trial_user.try(:trial_dog_name)
            end

            order_delivery_date = order_schedule.next_occurrence(Time.zone.at(order.created_at))

            plan_units = order_line_item.fulfillment_quantity
            plan_name = order_line_item.entity_id

            if plan_name == "1-lb-kabo-meal"
              days_in_interval = "TRIAL"
              plan_daily_serving = "TRIAL"
              adjusted_plan_daily_serving = "TRIAL"
            elsif ["chicken_2_weeks-trial",
              "beef_2_weeks-trial",
              "turkey_2_weeks-trial",
              "chicken_4_weeks-trial",
              "beef_4_weeks-trial",
              "turkey_4_weeks-trial"].include?(plan_name) || plan_name.start_with?("chicken_2_weeks") || plan_name.start_with?("beef_2_weeks") || plan_name.start_with?("turkey_2_weeks") || plan_name.start_with?("chicken_4_weeks") || plan_name.start_with?("beef_4_weeks") || plan_name.start_with?("turkey_4_weeks")
              combined_sku.push(plan_name.split("_")[0])
              combined_plan_units += plan_units

              order_line_items_filtered = order.order_line_items.select { |a|
                ["chicken_2_weeks-trial",
                "beef_2_weeks-trial",
                "turkey_2_weeks-trial",
                "chicken_4_weeks-trial",
                "beef_4_weeks-trial",
                "turkey_4_weeks-trial"].include?(a.entity_id) || a.entity_id.start_with?("chicken_2_weeks") || a.entity_id.start_with?("beef_2_weeks") || a.entity_id.start_with?("turkey_2_weeks") || a.entity_id.start_with?("chicken_4_weeks") || a.entity_id.start_with?("beef_4_weeks") || a.entity_id.start_with?("turkey_4_weeks")
              }

              next if order_line_items_filtered.count > 1 && order_line_items_filtered.last.id != order_line_item.id

              # combined_plan_units = plan_units*order.order_line_items.count
              days_in_interval = plan_name.split("_")[1].to_i*7
              plan_daily_serving = combined_plan_units/days_in_interval

              dog_record = database_records[order.try(:subscription_id)]
              if dog_record
                plan_name = "#{dog_record[:cooked_portion].blank? ? "45" : dog_record[:cooked_portion]}_#{combined_sku.sort.join("+")}_#{plan_name.split("_")[1]}_weeks"
              else
                plan_name = "NO DOG LINKED TO ORDER - #{combined_sku.sort.join("+")}_#{plan_name.split("_")[1]}_weeks"
              end
              line_item_name = "Mealplan v2"

              case plan_daily_serving
              when 0..2
                adjusted_plan_daily_serving = 2
              when 3..5
                adjusted_plan_daily_serving = 4
              else
                if plan_daily_serving.odd?
                  adjusted_plan_daily_serving = plan_daily_serving - 1
                else
                  adjusted_plan_daily_serving = plan_daily_serving
                end
              end
            elsif ["chicken_5lb_kibble-trial", "chicken_5lb_kibble-upsell-trial", "chicken_5lb_kibble_2_weeks", "chicken_5lb_kibble_4_weeks"].include?(plan_name) || plan_name.start_with?("chicken_kibble_2_weeks") || plan_name.start_with?("turkey+salmon_kibble_2_weeks") || plan_name.start_with?("duck_kibble_2_weeks") || plan_name.start_with?("chicken_kibble_4_weeks") || plan_name.start_with?("turkey+salmon_kibble_4_weeks") || plan_name.start_with?("duck_kibble_4_weeks")

              next if order.status == "delivered"

              days_in_interval = plan_name.split("_")[2].to_i*7
              if days_in_interval == 0
                days_in_interval = plan_name.split("_")[3].to_i*7
              end

              if days_in_interval == 0
                days_in_interval = "KIBBLE"
              end

              plan_daily_serving = "KIBBLE"
              adjusted_plan_daily_serving = "KIBBLE"

            elsif plan_name.split("_")[2].to_i*7 == 0
              days_in_interval = plan_name.split("_")[3].to_i*7
              plan_daily_serving = "ERROR"
              adjusted_plan_daily_serving = "ERROR"
            else
              days_in_interval = plan_name.split("_")[2].to_i*7
              plan_daily_serving = plan_units/days_in_interval

              case plan_daily_serving
              when 0..2
                adjusted_plan_daily_serving = 2
              when 3..5
                adjusted_plan_daily_serving = 4
              else
                if plan_daily_serving.odd?
                  adjusted_plan_daily_serving = plan_daily_serving - 1
                else
                  adjusted_plan_daily_serving = plan_daily_serving
                end
              end
            end

            # Adding 3+ days of food for customers during the holiday delivery cycle
            # if !adjusted_plan_daily_serving.is_a?(String) && !days_in_interval.is_a?(String)
            #   originalServingInfo = sanitizeQuantity(adjusted_plan_daily_serving, days_in_interval)
            #   if originalServingInfo[2] == 0.5 # 0.5 packs per day
            #     days_in_interval += 4
            #   else
            #     days_in_interval += 3
            #   end
            # end

            fulfillment_center = ""
            delivery_days = ""

            if ["AB", "BC", "SK"].include?(order.shipping_address.state_code)
              loomis_delivery_day = MyLib::Account.delivery_date_offset_by_loomis_postal_code(order.shipping_address.zip)
              fedex_delivery_day = MyLib::Account.delivery_date_offset_by_fedex_postal_code(order.shipping_address.zip)

              if order.shipping_address.state_code == "AB" && [6, 7].include?(loomis_delivery_day)
                fulfillment_center = "Calgary_AB"
                delivery_days = loomis_delivery_day-5
              elsif order.shipping_address.state_code == "SK" && [6, 7].include?(loomis_delivery_day)
                fulfillment_center = "Calgary_AB"
                delivery_days = loomis_delivery_day-5
              elsif order.shipping_address.state_code == "BC" && [6, 7].include?(fedex_delivery_day)
                fulfillment_center = "Kelowna_BC"
                delivery_days = fedex_delivery_day-5
              elsif order.shipping_address.state_code == "BC" && [6, 7].include?(loomis_delivery_day)
                fulfillment_center = "Calgary_AB"
                delivery_days = loomis_delivery_day-5
              else
                fulfillment_center = "Kelowna_BC - Express Standard Overnight" # Switched to Kelowna for holiday delivery cycle
              end
            else
              fedex_delivery_day = MyLib::Account.delivery_date_offset_by_fedex_postal_code(order.shipping_address.zip)

              if fedex_delivery_day == 6
                fulfillment_center = "Mississauga_ON"
                delivery_days = fedex_delivery_day-5
              elsif fedex_delivery_day == 7
                fulfillment_center = "Mississauga_ON - Express" # Switched to Express for holiday delivery cycle
                delivery_days = fedex_delivery_day-5
              else
                fulfillment_center = "N/A"
                delivery_days = "N/A"
              end
            end

            if order.try(:shipping_address)
              kibble_order = (["chicken_5lb_kibble-trial", "chicken_5lb_kibble-upsell-trial", "chicken_5lb_kibble_2_weeks", "chicken_5lb_kibble_4_weeks"].include?(order_line_item.entity_id) || order_line_item.entity_id.start_with?("chicken_kibble_2_weeks") || order_line_item.entity_id.start_with?("turkey+salmon_kibble_2_weeks") || order_line_item.entity_id.start_with?("duck_kibble_2_weeks") || order_line_item.entity_id.start_with?("chicken_kibble_4_weeks") || order_line_item.entity_id.start_with?("turkey+salmon_kibble_4_weeks") || order_line_item.entity_id.start_with?("duck_kibble_4_weeks"))

              orders_to_ship.push({
                order_id: "#{order.document_number}#{(kibble_order) ? 'K_B'+plan_units.to_s : ''}",
                order_status: order.status,
                created_date: Time.zone.at(order.created_at).strftime("%d-%b-%y"),
                created_datetime: Time.zone.at(order.created_at).iso8601,
                human_name: human_name,
                email: email,
                animal_name: dog_name,
                line_item_quantity: ((combined_plan_units == 0 || kibble_order ? nil : combined_plan_units) || plan_units),
                line_item_name: (line_item_name || order_line_item.description),
                line_item_sku: plan_name,
                daily_serving_size_oz: plan_daily_serving,
                adjusted_daily_serving_size_oz: adjusted_plan_daily_serving,
                delivery_frequency: days_in_interval,
                total_weight_lbs: (plan_units/16).round(2),
                first_delivery_date: (order_delivery_date + 7.days).strftime("%d-%b-%y"),
                prep_by_date: (order_delivery_date + 7.days).strftime("%d-%b-%y"),
                food_restriction_custom: food_restriction_custom,
                first_order: first_order,
                # TODO
                subscription_comments: subscription_comments.join("\n"),
                number_of_dogs: dog_count,
                reference: order.document_number,
                name: "#{order.shipping_address.first_name},#{order.shipping_address.last_name}",
                street_address: order.shipping_address.line1,
                unit: order.shipping_address.line2,
                city: order.shipping_address.city,
                province: order.shipping_address.state_code,
                postal_code: order.shipping_address.zip,
                contact_name: "#{order.shipping_address.first_name} #{order.shipping_address.last_name}",
                phone_number: order.shipping_address.phone,
                pieces: 1,
                weight: (plan_units/16).round(2) + box_ice_weight_lbs, # in lbs
                delivery_instructions: order.shipping_address.line3,
                fulfillment_service: MyLib::Checkout.ace_postal_code(order.shipping_address.zip) ? "Atripco" : "", # Using text "Atripco" to support existing Apps Script functionality
                subscription_status: subscription_status,
                fulfillment_center: fulfillment_center,
                delivery_days: delivery_days,
                unique_order_id: order.id
              })
            else
              orders_to_ship.push({
                order_id: order.document_number,
                reference: order.document_number
              })
            end
          end
        end

        csv = CSV.generate(headers: true) do |_csv|
          _csv << [
            "OrderID",
            "OrderStatus",
            "CreatedDate",
            "CreatedDateTime",
            "HumanName",
            "Email",
            "AnimalName",
            "LineitemQuantity",
            "LineitemName",
            "LineitemSKU",
            "DailyServingSize (oz)",
            "AdjustedDailyServingSize (oz)",
            "DeliveryFrequency (days)",
            "TotalWeight (lbs)",
            "FirstDeliveryDate",
            "PrepByDate",
            "FoodRestrictionCustom",
            "FirstOrder",
            "SubscriptionComments",
            "NumberOfDogs",
            "Department",
            "Reference",
            "Name (First,Last or Company Name)",
            "Street Address",
            "Unit",
            "City",
            "Province",
            "Postal Code",
            "Contact Name",
            "Phone Number",
            "Pieces",
            "Weight",
            "Delivery Instructions",
            "Waybill #",
            "LineitemSKU",
            "AnimalName",
            "FirstOrder",
            "SubscriptionComments",
            "FulfillmentService",
            "SubscriptionStatus",
            "FulfillmentCenter",
            "DeliveryDays",
            "UniqueOrderID"
          ]

          orders_to_ship.each do |order|
            _csv << [
              order[:order_id], # Start of Production Export
              order[:order_status],
              order[:created_date],
              order[:created_datetime],
              order[:human_name],
              order[:email],
              order[:animal_name],
              order[:line_item_quantity],
              order[:line_item_name],
              order[:line_item_sku],
              order[:daily_serving_size_oz],
              order[:adjusted_daily_serving_size_oz],
              order[:delivery_frequency],
              order[:total_weight_lbs],
              order[:first_delivery_date],
              order[:prep_by_date],
              order[:food_restriction_custom],
              order[:first_order],
              order[:subscription_comments],
              order[:number_of_dogs],
              "", # Start of Shipping Export
              order[:reference],
              order[:name],
              order[:street_address],
              order[:unit],
              order[:city],
              order[:province],
              order[:postal_code],
              order[:contact_name],
              order[:phone_number],
              order[:pieces],
              order[:weight],
              order[:delivery_instructions],
              "",
              order[:line_item_sku],
              order[:animal_name],
              order[:first_order],
              order[:subscription_comments],
              order[:fulfillment_service],
              order[:subscription_status],
              order[:fulfillment_center],
              order[:delivery_days],
              order[:unique_order_id]
            ]
          end
        end

        csv
      end

      # Combined production + shipping export for one time purchases
      def orders_for_production_and_shipping_one_time_purchase
        current_schedule = IceCube::Schedule.new(Time.zone.parse("2019-03-29 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        previous_periods = current_schedule.previous_occurrences(2, Time.zone.now)

        order_cutoff_date = Time.zone.now

        order_list_offset = nil
        all_orders_list = []

        loop do
          order_list_query = {
            "status[in]" => ["queued", "awaiting_shipment"],
            "sort_by[asc]" => "created_at",
            "order_date[between]" => [previous_periods[0].utc.to_i, order_cutoff_date.utc.to_i],
            limit: 100
          }

          if order_list_offset
            order_list_query[:offset] = order_list_offset
          end

          current_query_list = ChargeBee::Order.list(order_list_query)

          current_query_list.each do |list_item|
            all_orders_list.push(list_item.order)
          end

          order_list_offset = current_query_list.next_offset
          break if order_list_offset.nil?
        end

        orders_to_ship = []

        order_schedule = IceCube::Schedule.new(Time.zone.parse("2019-03-29 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        all_orders_list.each do |order|
          next if order.try(:subscription_id) # Skipping subscription orders

          plan_name = order.order_line_items[0].entity_id
          plan_units = order.order_line_items[0].fulfillment_quantity

          trial_user = User.where(chargebee_customer_id: order.customer_id)
                            .select(:one_time_purchase_dog_names).first

          order_delivery_date = order_schedule.next_occurrence(Time.zone.at(order.created_at))

          if order.try(:shipping_address)

            orders_to_ship.push({
              order_id: order.document_number,
              order_status: order.status,
              created_date: Time.zone.at(order.created_at).strftime("%d-%b-%y"),
              human_name: "#{order.shipping_address.try(:first_name)} #{order.shipping_address.try(:last_name)}",
              email: order.shipping_address.email,
              animal_name: trial_user.try(:one_time_purchase_dog_names),
              line_item_quantity: plan_units,
              line_item_name: order.order_line_items[0].description,
              line_item_sku: plan_name,
              first_delivery_date: (order_delivery_date + MyLib::Account.delivery_date_offset_by_postal_code(order.shipping_address.zip)).strftime("%d-%b-%y"),
              # TODO
              reference: order.document_number,
              name: "#{order.shipping_address.first_name},#{order.shipping_address.last_name}",
              street_address: order.shipping_address.line1,
              unit: order.shipping_address.line2,
              city: order.shipping_address.city,
              province: order.shipping_address.state_code,
              postal_code: order.shipping_address.zip,
              contact_name: "#{order.shipping_address.first_name} #{order.shipping_address.last_name}",
              phone_number: order.shipping_address.phone,
              delivery_instructions: order.shipping_address.line3,
              fulfillment_service: MyLib::Checkout.ace_postal_code(order.shipping_address.zip) ? "ACE" : "",
            })
          else
            orders_to_ship.push({
              order_id: order.document_number,
              reference: order.document_number
            })
          end
        end

        csv = CSV.generate(headers: true) do |_csv|
          _csv << [
            "OrderID",
            "OrderStatus",
            "CreatedDate",
            "HumanName",
            "Email",
            "AnimalName",
            "LineitemQuantity",
            "LineitemName",
            "LineitemSKU",
            "FirstDeliveryDate",
            "Reference",
            "Name (First,Last or Company Name)",
            "Street Address",
            "Unit",
            "City",
            "Province",
            "Postal Code",
            "Contact Name",
            "Phone Number",
            "Delivery Instructions",
            "FulfillmentService"
          ]

          orders_to_ship.each do |order|
            _csv << [
              order[:order_id], # Start of Production Export
              order[:order_status],
              order[:created_date],
              order[:human_name],
              order[:email],
              order[:animal_name],
              order[:line_item_quantity],
              order[:line_item_name],
              order[:line_item_sku],
              order[:first_delivery_date],
              order[:reference], # Start of Shipping Export
              order[:name],
              order[:street_address],
              order[:unit],
              order[:city],
              order[:province],
              order[:postal_code],
              order[:contact_name],
              order[:phone_number],
              order[:delivery_instructions],
              order[:fulfillment_service]
            ]
          end
        end

        csv
      end

      def orders_for_production(before_date, include_all_before = false)
        if include_all_before
          current_schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
            s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
          end

          previous_period = current_schedule.previous_occurrences(2, before_date)

          order_cutoff_date = before_date

          list = ChargeBee::Order.list({
            "status[in]" => ["queued", "delivered"],
            "sort_by[asc]" => "created_at",
            "order_date[between]" => [previous_period[0].utc.to_i, order_cutoff_date.utc.to_i],
            limit: 100
          })

          if list.try(:next_offset)
            list2 = ChargeBee::Order.list({
              "status[in]" => ["queued", "delivered"],
              "sort_by[asc]" => "created_at",
              "order_date[between]" => [previous_period[0].utc.to_i, order_cutoff_date.utc.to_i],
              limit: 100,
              offset: list.next_offset
            })
          end
        else
          current_schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
            s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
          end

          order_cutoff_date = current_schedule.previous_occurrence(before_date)

          list = ChargeBee::Order.list({
            "status[is]" => "queued",
            "sort_by[asc]" => "created_at",
            "order_date[before]" => order_cutoff_date.utc.to_i,
            limit: 100
          })

          if list.try(:next_offset)
            list2 = ChargeBee::Order.list({
              "status[is]" => "queued",
              "sort_by[asc]" => "created_at",
              "order_date[before]" => order_cutoff_date.utc.to_i,
              limit: 100,
              offset: list.next_offset
            })
          end
        end

        orders_to_ship = []

        order_schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        list.each do |entry|
          food_restriction_custom = ""
          first_order = ""
          all_subscription_comments = []
          dog_count = "N/A"

          if entry.order.try(:subscription_id)
            # dog_name = User.where(chargebee_customer_id: entry.order.customer_id).first.dogs.first.name
            # human_name = "#{entry.order.shipping_address.first_name} #{entry.order.shipping_address.last_name}"
            subscription = ChargeBee::Subscription.retrieve(entry.order.subscription_id)
            dog_name = subscription.subscription.cf_dog_name
            human_name = "#{subscription.subscription.shipping_address.first_name} #{subscription.subscription.shipping_address.last_name}"

            dog_profile = Dog.where(chargebee_subscription_id: entry.order.subscription_id).first
            if !dog_profile.blank?
              # dog_name = dog_profile.name
              escaped_food_restriction_custom = %("#{dog_profile.food_restriction_custom}")
              food_restriction_custom = "#{escaped_food_restriction_custom}"
              dog_count = dog_profile.user.dogs.count
            else
              user_profile = User.where(chargebee_customer_id: entry.order.customer_id).first
              if !user_profile.blank?
                escaped_food_restriction_custom = %("#{user_profile.dogs.first.food_restriction_custom}")
                food_restriction_custom = "#{escaped_food_restriction_custom}"
                dog_count = user_profile.dogs.count
              end
            end

            # Check to see if order is within first interval (first order)
            first_subscription_schedule_renewal = order_schedule.next_occurrence(Time.zone.at(subscription.subscription.created_at))
            if Time.zone.at(entry.order.created_at) < first_subscription_schedule_renewal
              first_order = "YES"
            else
              first_order = "NO"
            end

            # Get subscription comments
            comments_list = ChargeBee::Comment.list({
              :limit => 100,
              "sort_by[asc]" => "created_at",
              "entity_type" => "subscription",
              "entity_id" => entry.order.subscription_id
              })
            comments_list.each do |comment|
              all_subscription_comments.push(comment.comment.notes)
            end
          else
            human_name = "#{entry.order.shipping_address.try(:first_name)} #{entry.order.shipping_address.try(:last_name)}"
            dog_name = User.where(chargebee_customer_id: entry.order.customer_id).first.try(:trial_dog_name)
          end

          order_delivery_date = order_schedule.next_occurrence(Time.zone.at(entry.order.created_at))

          plan_units = entry.order.order_line_items[0].fulfillment_quantity
          plan_name = entry.order.order_line_items[0].entity_id

          if plan_name == "1-lb-kabo-meal"
            days_in_interval = "TRIAL"
            plan_daily_serving = "TRIAL"
          else
            days_in_interval = plan_name.split("_")[2].to_i*7
            plan_daily_serving = plan_units/days_in_interval
          end

          orders_to_ship.push({
            order_id: entry.order.document_number,
            order_status: entry.order.status,
            created_date: Time.zone.at(entry.order.created_at).strftime("%d-%b-%y"),
            human_name: human_name,
            animal_name: dog_name,
            line_item_quantity: plan_units,
            line_item_name: entry.order.order_line_items[0].description,
            line_item_sku: plan_name,
            daily_serving_size_oz: plan_daily_serving,
            delivery_frequency: days_in_interval,
            total_weight_lbs: (plan_units/16).round(2),
            first_delivery_date: (order_delivery_date + 7.days).strftime("%d-%b-%y"),
            prep_by_date: (order_delivery_date + 7.days).strftime("%d-%b-%y"),
            food_restriction_custom: food_restriction_custom,
            first_order: first_order,
            subscription_comments: all_subscription_comments.join("\n"),
            number_of_dogs: dog_count
          })
        end

        if list.try(:next_offset)
          list2.each do |entry|
            food_restriction_custom = ""
            first_order = ""
            all_subscription_comments = []
            dog_count = "N/A"

            if entry.order.try(:subscription_id)
              # dog_name = User.where(chargebee_customer_id: entry.order.customer_id).first.dogs.first.name
              # human_name = "#{entry.order.shipping_address.first_name} #{entry.order.shipping_address.last_name}"
              subscription = ChargeBee::Subscription.retrieve(entry.order.subscription_id)
              dog_name = subscription.subscription.cf_dog_name
              human_name = "#{subscription.subscription.shipping_address.first_name} #{subscription.subscription.shipping_address.last_name}"

              dog_profile = Dog.where(chargebee_subscription_id: entry.order.subscription_id).first
              if !dog_profile.blank?
                # dog_name = dog_profile.name
                escaped_food_restriction_custom = %("#{dog_profile.food_restriction_custom}")
                food_restriction_custom = "#{escaped_food_restriction_custom}"
                dog_count = dog_profile.user.dogs.count
              else
                user_profile = User.where(chargebee_customer_id: entry.order.customer_id).first
                if !user_profile.blank?
                  escaped_food_restriction_custom = %("#{user_profile.dogs.first.food_restriction_custom}")
                  food_restriction_custom = "#{escaped_food_restriction_custom}"
                  dog_count = user_profile.dogs.count
                end
              end

              # Check to see if order is within first interval (first order)
              first_subscription_schedule_renewal = order_schedule.next_occurrence(Time.zone.at(subscription.subscription.created_at))
              if Time.zone.at(entry.order.created_at) < first_subscription_schedule_renewal
                first_order = "YES"
              else
                first_order = "NO"
              end

              # Get subscription comments
              comments_list = ChargeBee::Comment.list({
                :limit => 100,
                "sort_by[asc]" => "created_at",
                "entity_type" => "subscription",
                "entity_id" => entry.order.subscription_id
                })
              comments_list.each do |comment|
                all_subscription_comments.push(comment.comment.notes)
              end
            else
              human_name = "#{entry.order.shipping_address.try(:first_name)} #{entry.order.shipping_address.try(:last_name)}"
              dog_name = User.where(chargebee_customer_id: entry.order.customer_id).first.try(:trial_dog_name)
            end

            order_delivery_date = order_schedule.next_occurrence(Time.zone.at(entry.order.created_at))

            plan_units = entry.order.order_line_items[0].fulfillment_quantity
            plan_name = entry.order.order_line_items[0].entity_id

            if plan_name == "1-lb-kabo-meal"
              days_in_interval = "TRIAL"
              plan_daily_serving = "TRIAL"
            else
              days_in_interval = plan_name.split("_")[2].to_i*7
              plan_daily_serving = plan_units/days_in_interval
            end

            orders_to_ship.push({
              order_id: entry.order.document_number,
              order_status: entry.order.status,
              created_date: Time.zone.at(entry.order.created_at).strftime("%d-%b-%y"),
              human_name: human_name,
              animal_name: dog_name,
              line_item_quantity: plan_units,
              line_item_name: entry.order.order_line_items[0].description,
              line_item_sku: plan_name,
              daily_serving_size_oz: plan_daily_serving,
              delivery_frequency: days_in_interval,
              total_weight_lbs: (plan_units/16).round(2),
              first_delivery_date: (order_delivery_date + 7.days).strftime("%d-%b-%y"),
              prep_by_date: (order_delivery_date + 7.days).strftime("%d-%b-%y"),
              food_restriction_custom: food_restriction_custom,
              first_order: first_order,
              subscription_comments: all_subscription_comments.join("\n"),
              number_of_dogs: dog_count
            })
          end
        end

        csv = CSV.generate(headers: true) do |_csv|
          _csv << [
            "OrderID",
            "OrderStatus",
            "CreatedDate",
            "HumanName",
            "AnimalName",
            "LineitemQuantity",
            "LineitemName",
            "LineitemSKU",
            "DailyServingSize (oz)",
            "DeliveryFrequency (days)",
            "TotalWeight (lbs)",
            "FirstDeliveryDate",
            "PrepByDate",
            "FoodRestrictionCustom",
            "FirstOrder",
            "SubscriptionComments",
            "NumberOfDogs"
          ]

          orders_to_ship.each do |order|
            _csv << [
              order[:order_id],
              order[:order_status],
              order[:created_date],
              order[:human_name],
              order[:animal_name],
              order[:line_item_quantity],
              order[:line_item_name],
              order[:line_item_sku],
              order[:daily_serving_size_oz],
              order[:delivery_frequency],
              order[:total_weight_lbs],
              order[:first_delivery_date],
              order[:prep_by_date],
              order[:food_restriction_custom],
              order[:first_order],
              order[:subscription_comments],
              order[:number_of_dogs]
            ]
          end
        end

        csv
      end

      def orders_for_shipping(before_date, include_all_before = false)
        box_ice_weight_lbs = 1

        if include_all_before
          order_cutoff_date = before_date
        else
          schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
            s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
          end

          order_cutoff_date = schedule.previous_occurrence(before_date)
        end

        list = ChargeBee::Order.list({
          "status[in]" => ["queued", "delivered"],
          "sort_by[asc]" => "created_at",
          "order_date[before]" => order_cutoff_date.utc.to_i,
          limit: 100
        })

        if list.try(:next_offset)
          list2 = ChargeBee::Order.list({
            "status[in]" => ["queued", "delivered"],
            "sort_by[asc]" => "created_at",
            "order_date[before]" => order_cutoff_date.utc.to_i,
            limit: 100,
            offset: list.next_offset
          })
        end

        orders_to_ship = []

        order_schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
          s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
        end

        list.each do |entry|
          plan_units = entry.order.order_line_items[0].fulfillment_quantity
          first_order = ""
          all_subscription_comments = []

          if entry.try(:order).try(:shipping_address)

            if entry.order.try(:subscription_id)
              subscription = ChargeBee::Subscription.retrieve(entry.order.subscription_id)
              dog_name = subscription.subscription.cf_dog_name

              # Check to see if order is within first interval (first order)
              first_subscription_schedule_renewal = order_schedule.next_occurrence(Time.zone.at(subscription.subscription.created_at))
              if Time.zone.at(entry.order.created_at) < first_subscription_schedule_renewal
                first_order = "YES"
              else
                first_order = "NO"
              end

              # Get subscription comments
              comments_list = ChargeBee::Comment.list({
                :limit => 100,
                "sort_by[asc]" => "created_at",
                "entity_type" => "subscription",
                "entity_id" => entry.order.subscription_id
                })
              comments_list.each do |comment|
                all_subscription_comments.push(comment.comment.notes)
              end
            else
              customer_result = ChargeBee::Customer.retrieve(entry.order.customer_id)
              dog_name = customer_result.customer.cf_trial_dog_name
            end

            plan_name = entry.order.order_line_items[0].entity_id

            orders_to_ship.push({
              reference: entry.order.document_number,
              name: "#{entry.order.shipping_address.first_name},#{entry.order.shipping_address.last_name}",
              street_address: entry.order.shipping_address.line1,
              unit: entry.order.shipping_address.line2,
              city: entry.order.shipping_address.city,
              province: entry.order.shipping_address.state_code,
              postal_code: entry.order.shipping_address.zip,
              contact_name: "#{entry.order.shipping_address.first_name} #{entry.order.shipping_address.last_name}",
              phone_number: entry.order.shipping_address.phone,
              pieces: 1,
              weight: (plan_units/16).round(2) + box_ice_weight_lbs, # in lbs
              delivery_instructions: entry.order.shipping_address.line3,
              line_item_sku: plan_name,
              animal_name: dog_name,
              first_order: first_order,
              subscription_comments: all_subscription_comments.join("\n")
            })
          else
            orders_to_ship.push({
              reference: entry.order.document_number
            })
          end
        end

        if list.try(:next_offset)
          list2.each do |entry|
            plan_units = entry.order.order_line_items[0].fulfillment_quantity
            first_order = ""
            all_subscription_comments = []

            if entry.try(:order).try(:shipping_address)

              if entry.order.try(:subscription_id)
                subscription = ChargeBee::Subscription.retrieve(entry.order.subscription_id)
                dog_name = subscription.subscription.cf_dog_name

                # Check to see if order is within first interval (first order)
                first_subscription_schedule_renewal = order_schedule.next_occurrence(Time.zone.at(subscription.subscription.created_at))
                if Time.zone.at(entry.order.created_at) < first_subscription_schedule_renewal
                  first_order = "YES"
                else
                  first_order = "NO"
                end

                # Get subscription comments
                comments_list = ChargeBee::Comment.list({
                  :limit => 100,
                  "sort_by[asc]" => "created_at",
                  "entity_type" => "subscription",
                  "entity_id" => entry.order.subscription_id
                  })
                comments_list.each do |comment|
                  all_subscription_comments.push(comment.comment.notes)
                end
              else
                customer_result = ChargeBee::Customer.retrieve(entry.order.customer_id)
                dog_name = customer_result.customer.cf_trial_dog_name
              end

              plan_name = entry.order.order_line_items[0].entity_id

              orders_to_ship.push({
                reference: entry.order.document_number,
                name: "#{entry.order.shipping_address.first_name},#{entry.order.shipping_address.last_name}",
                street_address: entry.order.shipping_address.line1,
                unit: entry.order.shipping_address.line2,
                city: entry.order.shipping_address.city,
                province: entry.order.shipping_address.state_code,
                postal_code: entry.order.shipping_address.zip,
                contact_name: "#{entry.order.shipping_address.first_name} #{entry.order.shipping_address.last_name}",
                phone_number: entry.order.shipping_address.phone,
                pieces: 1,
                weight: (plan_units/16).round(2) + box_ice_weight_lbs, # in lbs
                delivery_instructions: entry.order.shipping_address.line3,
                line_item_sku: plan_name,
                animal_name: dog_name,
                first_order: first_order,
                subscription_comments: all_subscription_comments.join("\n")
              })
            else
              orders_to_ship.push({
                reference: entry.order.document_number
              })
            end
          end
        end

        csv = CSV.generate(headers: true) do |_csv|
          _csv << [
            "Department",
            "Reference",
            "Name (First,Last or Company Name)",
            "Street Address",
            "Unit",
            "City",
            "Province",
            "Postal Code",
            "Contact Name",
            "Phone Number",
            "Pieces",
            "Weight",
            "Delivery Instructions",
            "Waybill #",
            "LineitemSKU",
            "AnimalName",
            "FirstOrder",
            "SubscriptionComments"
          ]

          orders_to_ship.each do |order|
            _csv << [
              "",
              order[:reference],
              order[:name],
              order[:street_address],
              order[:unit],
              order[:city],
              order[:province],
              order[:postal_code],
              order[:contact_name],
              order[:phone_number],
              order[:pieces],
              order[:weight],
              order[:delivery_instructions],
              "",
              order[:line_item_sku],
              order[:animal_name],
              order[:first_order],
              order[:subscription_comments]
            ]
          end
        end

        csv
      end

      # Cancelled subscriptions within a certain time period
      def cancelled_subscriptions(cancelled_from_date = DateTime.now.prev_month.beginning_of_month, cancelled_to_date = DateTime.now.prev_month.end_of_month)
        subscription_list_offset = nil
        all_subscriptions = []
        cancelled_subscriptions = []

        loop do
          subscription_list_query = {
            "status[in]" => ["cancelled"],
            "cancelled_at[between]" => [cancelled_from_date.utc.to_i, cancelled_to_date.utc.to_i],
            limit: 100
          }

          if subscription_list_offset
            subscription_list_query[:offset] = subscription_list_offset
          end

          current_query_list = ChargeBee::Subscription.list(subscription_list_query)

          current_query_list.each do |cql|
            all_subscriptions.push(cql)
          end

          subscription_list_offset = current_query_list.next_offset
          break if subscription_list_offset.nil?
        end

        all_subscriptions.each do |subscription|
          cancelled_subscriptions.push({
            subscription_id: subscription.subscription.id,
            customer_name: "#{subscription.customer.first_name} #{subscription.customer.last_name}",
            email: subscription.customer.email,
            dog_name: subscription.subscription.cf_dog_name,
            cancelled_at: Time.zone.at(subscription.subscription.cancelled_at).to_s(:db),
          })
        end

        csv = CSV.generate(headers: true) do |_csv|
          _csv << [
            "SubscriptionID",
            "CustomerName",
            "Email",
            "DogName",
            "CancelledAt"
          ]

          cancelled_subscriptions.each do |subscription|
            _csv << [
              subscription[:subscription_id],
              subscription[:customer_name],
              subscription[:email],
              subscription[:dog_name],
              subscription[:cancelled_at],
            ]
          end
        end

        csv
      end
    end
  end
end
