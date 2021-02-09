# frozen_string_literal: true

module MyLib
  class Account
    class << self
      def delivery_date_offset(subscription)
        postal_code = subscription.shipping_address.zip

        delivery_date_offset_by_postal_code(postal_code)
      end

      def delivery_date_offset_by_postal_code(postal_code)
        ActiveRecord::Base.logger.silence do
          return 7.days if MyLib::Checkout.ace_postal_code(postal_code)

          postal_code_match = []

          postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..2].upcase, fsa: true).first.try(:delivery_day)
          postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..4].upcase, loomis: true).first.try(:delivery_day)
          postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..5].upcase, fedex: true).first.try(:delivery_day)

          return postal_code_match.compact.sort.first.days if postal_code_match.compact.sort.first

          return 7.days
        end
      end

      def delivery_date_for_kibble_offset_by_postal_code(postal_code)
        postal_code_match = []

        postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..2].upcase, fsa: true).where.not(province: "ON").first.try(:delivery_day)
        postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..4].upcase, loomis: true).where.not(province: "ON").first.try(:delivery_day)
        postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..5].upcase, fedex: true).where.not(province: "ON").first.try(:delivery_day)

        return (postal_code_match.compact.sort.first - 3).days if postal_code_match.compact.sort.first

        7.days
      end

      def delivery_date_offset_by_loomis_postal_code(postal_code)
        postal_code_match = ServiceablePostalCode.where(postal_code: postal_code[0..4].upcase, loomis: true).first.try(:delivery_day)
        return postal_code_match if postal_code_match

        nil
      end

      def delivery_date_offset_by_fedex_postal_code(postal_code)
        postal_code_match = []

        postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..2].upcase, fsa: true).first.try(:delivery_day)
        postal_code_match.push ServiceablePostalCode.where(postal_code: postal_code[0..5].upcase, fedex: true).first.try(:delivery_day)

        return postal_code_match.compact.sort.first if postal_code_match.compact.sort.first

        nil
      end

      def subscription_status_icon(status)
        case status
        when "paused"
          "#F4B30C"
        when "cancelled"
          "#C0C0C0"
        else
          "#25D61A"
        end
      end

      def subscription_status_text(status)
        case status
        when "paused"
          "Paused Subscription"
        when "cancelled"
          "Cancelled Subscription"
        else
          "Active Subscription"
        end
      end

      def subscription_phase(subscription, skipped_first_box, mock_run_variables = {}, user = nil)
        current_time = Time.zone.now

        if Rails.configuration.heroku_app_name != "kabo-app" && Rails.configuration.heroku_app_name != "kabo-beta" && user && !user.qa_jump_by_days.nil? && !user.qa_jump_by_days.zero?
          current_time = Time.zone.now + user.qa_jump_by_days.days
        end

        if subscription
          plan_weeks = subscription.plan_id.split("_")[2].to_i.weeks

          plan_split = subscription.plan_id.split("_")
          if plan_split.count == 4
            plan_weeks = plan_split[2].to_i.weeks
          elsif plan_split[5] == "week-delay"
            plan_weeks = plan_split[4].to_i.weeks
          end

          cf_trial_start_date = subscription.cf_trial_start_date
          cf_resume_start_date = subscription.cf_resume_start_date
          activated_at = subscription.activated_at
          next_billing_at = subscription.next_billing_at
          start_date = subscription.start_date
          current_term_start = subscription.current_term_start
          delivery_date_offset_days = delivery_date_offset(subscription)
          if user.try(:trial_length)
            trial_length = user.trial_length.weeks
          else
            trial_length = 2.weeks
          end
        end

        if !mock_run_variables.empty?
          current_time = mock_run_variables[:current_time].change(offset: "-0400")
          plan_weeks = mock_run_variables[:plan_weeks]
          cf_trial_start_date = mock_run_variables[:cf_trial_start_date].change(offset: "-0400").to_i
          if !mock_run_variables[:activated_at].nil?
            activated_at = mock_run_variables[:activated_at].change(offset: "-0400").to_i
          else
            activated_at = mock_run_variables[:activated_at].to_i
          end
          next_billing_at = mock_run_variables[:next_billing_at].change(offset: "-0400").to_i
          start_date = mock_run_variables[:start_date].change(offset: "-0400").to_i
          if mock_run_variables[:current_term_start]
            current_term_start = mock_run_variables[:current_term_start].change(offset: "-0400").to_i
          end
          delivery_date_offset_days = delivery_date_offset_by_postal_code(mock_run_variables[:postal_code])
          trial_length = 2.weeks
        end

        if cf_resume_start_date && Time.zone.at(cf_resume_start_date) + delivery_date_offset_days > current_time
          {
            status: "waiting_for_resume_shipment",
            date: Time.zone.at(cf_resume_start_date) + delivery_date_offset_days
          }
        elsif Time.zone.at(cf_trial_start_date) + delivery_date_offset_days > current_time
          {
            status: "waiting_for_trial_shipment",
            date: Time.zone.at(cf_trial_start_date) + delivery_date_offset_days
          }
        elsif current_time > Time.zone.at(cf_trial_start_date) + delivery_date_offset_days &&
          (current_time < (Time.zone.at(cf_trial_start_date) + trial_length).change({ hour: 9, min: 0, sec: 0 }) ||
          (skipped_first_box && current_time < (Time.zone.at(start_date || activated_at) - 5.days).end_of_day))
          # base this off cf_trial_start_date to stop it from changing on user side when VJ bumps date in ChargeBee
          {
            status: "in_trial",
            date: Time.zone.at(cf_trial_start_date) + trial_length + delivery_date_offset_days,
            skip_date: Time.zone.at(cf_trial_start_date) + delivery_date_offset_days + (trial_length*2),
            skip_date_billing: Time.zone.at(cf_trial_start_date) + (trial_length*2),
            changes_applied_delivery_date: Time.zone.at(cf_trial_start_date) + trial_length + delivery_date_offset_days
          }
        elsif current_time > (Time.zone.at(cf_trial_start_date) + trial_length).change({ hour: 9, min: 0, sec: 0 }) &&
          current_time < Time.zone.at(cf_trial_start_date) + trial_length + delivery_date_offset_days
          {
            status: "first_box_preparing_order",
            date: Time.zone.at(cf_trial_start_date) + trial_length + delivery_date_offset_days,
            changes_applied_delivery_date: Time.zone.at(cf_trial_start_date) + trial_length + plan_weeks + delivery_date_offset_days
          }
        elsif ((skipped_first_box && current_time > (Time.zone.at(start_date || activated_at) - 5.days).end_of_day) &&
          current_time < (Time.zone.at(start_date || activated_at)).change({ hour: 11, min: 59, sec: 0 })) ||
          (((!skipped_first_box && start_date) || (skipped_first_box && !start_date) || (!skipped_first_box && !start_date)) &&
          current_time > Time.zone.at(current_term_start) + delivery_date_offset_days &&
          current_time < (Time.zone.at(next_billing_at)).change({ hour: 11, min: 59, sec: 0 }))

          {
            status: "normal_user_scheduled_order",
            date: Time.zone.at(next_billing_at) + delivery_date_offset_days,
            changes_applied_delivery_date: Time.zone.at(next_billing_at) + delivery_date_offset_days
          }
        elsif (current_time > (Time.zone.at(next_billing_at)).change({ hour: 11, min: 59, sec: 0 }) && current_time < Time.zone.at(next_billing_at)) ||
          (current_time > Time.zone.at(current_term_start) && current_time < (Time.zone.at(current_term_start) + delivery_date_offset_days).beginning_of_day)

          if current_time > (Time.zone.at(next_billing_at)).change({ hour: 11, min: 59, sec: 0 }) && current_time < Time.zone.at(next_billing_at)
            normal_user_preparing_order_date = Time.zone.at(next_billing_at) + delivery_date_offset_days
          elsif current_time > Time.zone.at(current_term_start) && current_time < (Time.zone.at(current_term_start) + delivery_date_offset_days).beginning_of_day
            normal_user_preparing_order_date = Time.zone.at(current_term_start) + delivery_date_offset_days
          end
          {
            status: "normal_user_preparing_order",
            date: normal_user_preparing_order_date,
            changes_applied_delivery_date: Time.zone.at(next_billing_at) + delivery_date_offset_days
          }
        elsif current_time.to_date == (Time.zone.at(current_term_start) + delivery_date_offset_days).to_date
          {
            status: "normal_user_delivering_order",
            date: Time.zone.at(current_term_start) + delivery_date_offset_days,
            changes_applied_delivery_date: Time.zone.at(next_billing_at) + delivery_date_offset_days
          }
        else
          {
            status: "normal_user",
            changes_applied_delivery_date: Time.now
          }
        end
      end

      # Get cooked recipes
      def cooked_recipes
        [
          {
            name: "Tender Chicken",
            recipe: "chicken",
            image: nil,
            description: "A lean protein diet with hearty grains. Made with Canadian-sourced chicken.",
            new: false,
            analysis: Constants::CHICKEN_ANALYSIS
          },
          {
            name: "Savoury Beef",
            recipe: "beef",
            image: nil,
            description: "A grain-free diet, perfect for picky eaters! Made from locally-sourced beef.",
            new: false,
            analysis: Constants::BEEF_ANALYSIS
          },
          {
            name: "Hearty Turkey",
            recipe: "turkey",
            image: nil,
            description: "Made with lean, locally-sourced turkey breast. Low-Fat. Gluten-Free.",
            new: false,
            analysis: Constants::TURKEY_ANALYSIS
          },
          {
            name: "Luscious Lamb",
            recipe: "lamb",
            image: nil,
            description: "Made with premium Ontario lamb. A novel protein choice for picky eaters and senior dogs!",
            new: true,
            analysis: Constants::LAMB_ANALYSIS
          }
        ]
      end

      # Get kibble recipes
      def kibble_recipes
        [
          {
            name: "Chicken",
            recipe: "chicken",
            image: nil,
            description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
            new: false,
            analysis: Constants::CHICKEN_KIBBLE_ANALYSIS
          },
          {
            name: "Turkey & Salmon",
            recipe: "turkey+salmon",
            image: nil,
            description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
            new: false,
            analysis: Constants::TURKEY_SALMON_KIBBLE_ANALYSIS
          },
          {
            name: "Duck",
            recipe: "duck",
            image: nil,
            description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
            new: false,
            analysis: Constants::DUCK_KIBBLE_ANALYSIS
          }
        ]
      end
    end
  end
end
