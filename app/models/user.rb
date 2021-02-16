# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable, :rememberable, :registerable
  devise :database_authenticatable, :recoverable, :validatable, :trackable

  include Userable

  # Relations
  has_many :dogs, dependent: :destroy
  accepts_nested_attributes_for :dogs

  before_update :create_customer_and_subscription
  after_create :send_to_klaviyo

  attr_accessor :shipping_first_name,
    :shipping_last_name,
    :shipping_street_address,
    :shipping_apt_suite,
    :shipping_city,
    :shipping_province,
    :shipping_postal_code,
    :shipping_phone_number,
    :shipping_delivery_instructions,
    :same_billing_address,
    :billing_first_name,
    :billing_last_name,
    :billing_street_address,
    :billing_apt_suite,
    :billing_city,
    :billing_province,
    :billing_postal_code,
    :billing_phone_number,
    :stripe_type,
    :stripe_token,
    :reference_id,
    :alt_email,
    :alt_postal_code,
    :confirm_password,
    :amount_of_food,
    :how_often,
    :starting_date,
    :fbc,
    :fbp

  # Validations
  validates_each :shipping_postal_code do |record, attr, value|
    if value.present?
      unless value.length == 6 && MyLib::Checkout.serviceable_postal_code(value)
        if Rails.env.production?
          begin
            notifier = Slack::Notifier.new Rails.configuration.slack_webhooks[:growth]
            notifier.post text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{record.email} just tried to use an unserviceable postal code - #{value}", icon_emoji: ":octagonal_sign:"
          rescue StandardError => e
            Raven.capture_exception(e)
          end
        end
        record.errors.add(:base, "Sorry! Kabo is only available in Ontario, Quebec, British Columbia, Alberta, and select cities in Manitoba, Saskatchewan, New Brunswick, and Nova Scotia")
      end
    end
  end

  def email_sha1
    Digest::SHA1.hexdigest(email)
  end

  def delivery_address_edit_disabled
    schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
      s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
    end

    trial_start_date = schedule.next_occurrence(first_checkout_at) # .utc.to_i

    # Disable if purchased before Sunday (mid cycle), and current date is after
    # Disable if purchased before Friday @ noon, and current date is after
    if subscription_phase_status == "waiting_for_trial_shipment" &&
      ((first_checkout_at < trial_start_date - 5.days && DateTime.now > trial_start_date - 5.days) ||
      (first_checkout_at >= trial_start_date - 5.days && first_checkout_at < trial_start_date && DateTime.now > trial_start_date))
      true
    elsif subscription_phase_status == "waiting_for_resume_shipment"
      true
    else
      false
    end
  end

  def postal_code=(pc)
    if pc
      super pc.upcase
    end
  end

  def amount_of_food
    if chargebee_plan_interval.include?("2_weeks") then "2_weeks"
    elsif chargebee_plan_interval.include?("4_weeks") then "4_weeks"
    else nil
    end
  end

  def readable_chargebee_plan_interval(split = false)
    plan_split = chargebee_plan_interval.split("_")
    if plan_split.size == 2
      split ? ["#{plan_split[0]} weeks of food", "every #{plan_split[0]} weeks"] : "#{plan_split[0]} weeks of food every #{plan_split[0]} weeks"
    elsif plan_split[3] == "week-delay"
      split ? ["#{plan_split[0]} weeks of food", "every #{plan_split[2]} weeks"] : "#{plan_split[0]} weeks of food every #{plan_split[2]} weeks"
    end
  end

  def serviceable_postal_code
    postal_code_override ? true : MyLib::Checkout.serviceable_postal_code(postal_code)
  end

  def send_to_klaviyo
    if Rails.env.production?
      begin
        if email.exclude? Rails.configuration.emails[:temp_user] # excluding users that skip email on the onboarding
          klaviyo_response = RestClient.post "https://a.klaviyo.com/api/v2/list/LTjrjX/subscribe",
            {
              api_key: Rails.configuration.klaviyo_api_key,
              "profiles": [
                {
                  "email": email,
                  "First Name": first_name,
                  "Dog Name": dogs.map { |dog| dog.name }.join(" & "),
                  "Checkout URL": "https://kabo.co/checkout/#{checkout_token}",
                  "Checkout Price Total": MyLib::Checkout.estimate_v2(self, dogs.last, "40off")[:priceTotal][:details]
                }
              ]
            }.to_json, { content_type: :json, accept: :json }

          klaviyo_user_id = JSON.parse(klaviyo_response.body)[0]["id"]

          update_column(:klaviyo_id, klaviyo_user_id)
        end
      rescue StandardError => e
        puts "ERROR: #{e.message}"
      end
    end
  end

  def calculated_trial_length
    (dogs.size == 1 && !dogs.first.topper_available) ? 4 : 2
  end

  def amount_of_food_options
    if trial_length == 4 then [["4 weeks of food", "4_weeks"]]
    else [["2 weeks of food", "2_weeks"], ["4 weeks of food", "4_weeks"]]
    end
  end

  def how_often_options
    if trial_length == 4 then [["every 4 weeks", "4_week-delay"], ["every 6 weeks", "6_week-delay"], ["every 8 weeks", "8_week-delay"], ["every 12 weeks (3 months)", "12_week-delay"], ["every 26 weeks (6 months)", "26_week-delay"]]
    else [["every 2 weeks", "2_week-delay"], ["every 4 weeks", "4_week-delay"], ["every 6 weeks", "6_week-delay"], ["every 8 weeks", "8_week-delay"], ["every 12 weeks (3 months)", "12_week-delay"], ["every 26 weeks (6 months)", "26_week-delay"]]
    end
  end

  def delivery_starting_date_options(subscription)
    # Regular Subscription Customer
    schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 09:00:00")) do |s|
      s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
    end

    current_time = Time.zone.now

    if Rails.configuration.heroku_app_name != "kabo-app" && Rails.configuration.heroku_app_name != "kabo-beta" && !qa_jump_by_days.nil? && !qa_jump_by_days.zero?
      current_time = Time.zone.now + qa_jump_by_days.days
    end

    schedule.next_occurrences(3, current_time).map { |date| [((date + 3.hours) + MyLib::Account.delivery_date_offset(subscription)).strftime("%b %e") + (date.to_i == 1608300000 ? " (Potential Delivery Delays)" : ""), (date + 3.hours).to_i] }
  end

  def create_customer_and_subscription
    return if admin

    if chargebee_customer_id.blank? && !one_time_purchase
      if trial
        # create customer
        customer_result = ChargeBee::Customer.create({
          first_name: shipping_first_name,
          last_name: shipping_last_name,
          email: email,
          phone: shipping_phone_number,
          payment_method: {
            type: "card",
            tmp_token: stripe_token
          },
          billing_address: {
            first_name: billing_first_name,
            last_name: billing_last_name,
            line1: billing_street_address,
            line2: billing_apt_suite,
            city: billing_city,
            state: billing_province,
            zip: billing_postal_code,
            country: "CA",
            phone: billing_phone_number,
            email: email
          },
          cf_trial_dog_name: trial_dog_name
        })
        # create one-off invoice for customer

        ChargeBee::Invoice.create({
          customer_id: customer_result.customer.id,
          shipping_address: {
            first_name: shipping_first_name,
            last_name: shipping_last_name,
            line1: shipping_street_address,
            line2: shipping_apt_suite,
            line3: shipping_delivery_instructions,
            city: shipping_city,
            state_code: shipping_province,
            zip: shipping_postal_code,
            country: "CA",
            phone: shipping_phone_number,
            email: email
          },
          addons: [
            {
              id: "1-lb-kabo-meal",
              quantity: 16
            },
            {
              id: "free-sample-shipping"
            }
          ]
        })
      else
        # Regular Subscription Customer
        if dogs.map { |d| d.turkey_recipe }.include?(true) || dogs.map { |d| ["turkey+salmon", "duck"].include?(d.kibble_recipe) }.include?(true)
          # Delay cycle for new recipes
          schedule = IceCube::Schedule.new(Time.zone.parse("2020-11-20 12:00:00")) do |s|
            s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
          end
        else
          schedule = IceCube::Schedule.new(Time.zone.parse("2020-01-03 12:00:00")) do |s|
            s.add_recurrence_rule IceCube::Rule.weekly(2).day(:friday)
          end
        end

        trial_start_date = schedule.next_occurrences(2)[0].utc.to_i
        if chargebee_plan_interval == "4_weeks"
          subscription_start_date = schedule.next_occurrences(4)[2].utc.to_i
        else
          subscription_start_date = schedule.next_occurrences(2)[1].utc.to_i
        end

        begin
          if stripe_token.present?
            payment_method = {
              type: stripe_type,
              tmp_token: stripe_token
            }
          else
            payment_method = {
              type: "paypal_express_checkout",
              reference_id: reference_id
            }
          end

          # Create customer
          customer_result = ChargeBee::Customer.create({
            first_name: shipping_first_name,
            last_name: shipping_last_name,
            email: email,
            phone: shipping_phone_number,
            payment_method: payment_method,
            billing_address: {
              first_name: billing_first_name,
              last_name: billing_last_name,
              line1: billing_street_address,
              line2: billing_apt_suite,
              city: billing_city,
              state: billing_province,
              zip: billing_postal_code,
              country: "CA",
              phone: billing_phone_number,
              email: email
            }
          })
        rescue ChargeBee::PaymentError=> ex
          AirtableWorker.perform_async(
            table_id: "appO8lrXXmebSAgMU",
            view_name: "Customers",
            record: {
              "Email": email,
              "Error Text": ex.message,
              "Error Code": ex.api_error_code,
              "Action": "Main Checkout"
            }
          )

          self.errors.add(:base, "Sorry, there was a problem with your payment method, please check the details and try again")
          raise ActiveRecord::Rollback
        rescue StandardError => e
          self.errors.add(:base, "Sorry, there was a problem processing your checkout, please try again")
          Raven.capture_exception(e)
          raise ActiveRecord::Rollback
        end

        dogs.each do |dog|
          # Create subscription for dog associated to customer

          # add addon for lower AOV customers, only if the customer has 1 dog
          subscription_param_addons = []
          subscription_event_based_addons = []

          # RECURRING ADDONS
          subscription_param_addons.push({
            id: "beef_#{chargebee_plan_interval}",
            unit_price: unit_price("beef_#{chargebee_plan_interval}"),
            quantity: dog.plan_units_v2
          }) if dog.beef_recipe

          subscription_param_addons.push({
            id: "chicken_#{chargebee_plan_interval}",
            unit_price: unit_price("chicken_#{chargebee_plan_interval}"),
            quantity: dog.plan_units_v2
          }) if dog.chicken_recipe

          subscription_param_addons.push({
            id: "turkey_#{chargebee_plan_interval}",
            unit_price: unit_price("turkey_#{chargebee_plan_interval}"),
            quantity: dog.plan_units_v2
          }) if dog.turkey_recipe

          subscription_param_addons.push({
            id: "lamb_#{chargebee_plan_interval}",
            unit_price: unit_price("lamb_#{chargebee_plan_interval}"),
            quantity: dog.plan_units_v2
          }) if dog.lamb_recipe

          subscription_param_addons.push({
            id: "#{dog.kibble_recipe}_kibble_#{chargebee_plan_interval}",
            quantity: dog.kibble_quantity_v2
          }) if dog.kibble_recipe.present?

          # TRIAL ONE-TIME ADDONS
          subscription_event_based_addons.push({
            id: "beef_#{chargebee_plan_interval}-trial",
            unit_price: unit_price("beef_#{chargebee_plan_interval}"),
            quantity: dog.plan_units_v2,
            on_event: "subscription_creation",
            charge_once: true,
            charge_on: "on_event"
          }) if dog.beef_recipe

          subscription_event_based_addons.push({
            id: "chicken_#{chargebee_plan_interval}-trial",
            unit_price: unit_price("chicken_#{chargebee_plan_interval}"),
            quantity: dog.plan_units_v2,
            on_event: "subscription_creation",
            charge_once: true,
            charge_on: "on_event"
          }) if dog.chicken_recipe

          subscription_event_based_addons.push({
            id: "turkey_#{chargebee_plan_interval}-trial",
            unit_price: unit_price("turkey_#{chargebee_plan_interval}"),
            quantity: dog.plan_units_v2,
            on_event: "subscription_creation",
            charge_once: true,
            charge_on: "on_event"
          }) if dog.turkey_recipe

          subscription_event_based_addons.push({
            id: "#{dog.kibble_recipe}_kibble_#{chargebee_plan_interval}-trial",
            quantity: dog.kibble_quantity_v2,
            on_event: "subscription_creation",
            charge_once: true,
            charge_on: "on_event"
          }) if dog.kibble_recipe.present?

          begin
            subscription_result = ChargeBee::Subscription.create_for_customer(customer_result.customer.id, {
              plan_id: "#{chargebee_plan_interval}",
              shipping_address: {
                first_name: shipping_first_name,
                last_name: shipping_last_name,
                line1: shipping_street_address,
                line2: shipping_apt_suite,
                line3: shipping_delivery_instructions,
                city: shipping_city,
                state_code: shipping_province,
                zip: shipping_postal_code,
                country: "CA",
                phone: shipping_phone_number,
                email: email
              },
              coupon_ids: [referral_code],
              start_date: subscription_start_date,
              cf_trial_start_date: trial_start_date,
              cf_dog_name: dog.name,
              event_based_addons: subscription_event_based_addons,
              addons: subscription_param_addons
            })
          rescue ChargeBee::PaymentError=> ex
            AirtableWorker.perform_async(
              table_id: "appO8lrXXmebSAgMU",
              view_name: "Customers",
              record: {
                "Email": email,
                "Error Text": ex.message,
                "Error Code": ex.api_error_code,
                "Action": "Main Checkout"
              }
            )

            self.errors.add(:base, "Sorry, there was a problem with your payment method, please check the details and try again")
            raise ActiveRecord::Rollback
          rescue StandardError => e
            self.errors.add(:base, "Sorry, there was a problem processing your checkout, please try again")
            Raven.capture_exception(e)
            raise ActiveRecord::Rollback
          end
          dog.update_column(:chargebee_subscription_id, subscription_result.subscription.id)

          if dog.kibble_type.present?
            kibble_onboarding_slack_notification(dog)
          end

          begin
            AirtableWorker.perform_async(
              table_id: "appelmEF1Nqv0dOg0",
              view_name: "Customers",
              record: {
                "Email": email,
                "CB Customer ID": customer_result.customer.id,
                "Tender Chicken": dog.chicken_recipe,
                "Savoury Beef": dog.beef_recipe,
                "Hearty Turkey": dog.turkey_recipe,
                "Kibble Recipe": dog.kibble_recipe,
                "OZ per Cooked Recipe": (dog.chicken_recipe || dog.beef_recipe || dog.turkey_recipe) ? dog.plan_units_v2 : 0,
                "Kibble Quantity": dog.kibble_recipe.present? ? dog.kibble_quantity_v2 : 0,
                "Total Price": ("%.2f" % ((subscription_result.subscription.addons.map { |addon| addon.amount }.sum).to_i/100.0)).to_f,
                "Province": shipping_province
              }
            )
          rescue StandardError => e
            Raven.capture_exception(e)
          end
        end

        self.chargebee_customer_id = customer_result.customer.id
        self.verified = true

        begin
          if Rails.env.production? && Rails.configuration.heroku_app_name == "kabo-app"
            FacebookWorker.perform_async({
              fbc: fbc,
              fbp: fbp,
              email: email,
              user_id: id
            })

            LobAddressVerificationWorker.perform_async({
              shipping_street_address: shipping_street_address,
              shipping_apt_suite: shipping_apt_suite,
              shipping_city: shipping_city,
              shipping_province: shipping_province,
              shipping_postal_code: shipping_postal_code,
              email: email,
              chargebee_customer_id: chargebee_customer_id
            })
          end
        rescue StandardError => e
          Raven.capture_exception(e)
        end
      end
    end
  end

  def kibble_onboarding_slack_notification(dog)
    if Rails.env.production?
      SlackWorker.perform_async(
        hook_url: "https://hooks.slack.com/services/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",
        text: "#{ ('[' + Rails.configuration.heroku_app_name + '] ') if Rails.configuration.heroku_app_name != 'kabo-app' }#{email} checked out with #{dog.kibble_quantity} kibble #{'bag'.pluralize(dog.kibble_quantity)} for #{dog.name}"
      )
    end
  rescue StandardError => e
    Raven.capture_exception(e)
  end
end
