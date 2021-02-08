# frozen_string_literal: true

class Dog < ApplicationRecord
  include Dogable

  # Relations
  belongs_to :user

  # Validations
  validates_inclusion_of :neutered, in: [true, false]
  validates_inclusion_of :gender, in: [Constants::FEMALE, Constants::MALE]
  validates_inclusion_of :weight_unit, in: [Constants::LBS, Constants::KG]
  # validates_inclusion_of :meal_type, :in => Constants::MEAL_TYPES
  validates_inclusion_of :age_in_months, in: 0..240

  attr_accessor :turkey_quantity, :treat_quantity, :treat_sku

  def kibble_quantity(plan_interval = "",  _kibble_type = "")
    meal = _kibble_type.present? ? _kibble_type : kibble_type

    meal_percentage = meal.split("_")[0].to_i / 100.0
    calories_for_meal_per_day = meal_percentage * calories_required

    # 1667 calories per 1lb kibble, 8335 in a 5lb bag
    bags_for_meal_per_day = (calories_for_meal_per_day / 8335) # can be a fraction of a bag

    interval = plan_interval.present? ? plan_interval : user.chargebee_plan_interval

    ounces_for_meal_during_plan_interval = bags_for_meal_per_day * 14 # for 2 weeks

    if interval.include?("4_weeks")
      ounces_for_meal_during_plan_interval = ounces_for_meal_during_plan_interval*2
    end

    if kibble_type.include?("_bag_")
      kibble_type.split("_")[0]
    else
      ounces_for_meal_during_plan_interval.ceil # rounded up to the next amount of bags
    end
  end

  def daily_serving(plan_units, decimal = false)
    _plan_units = decimal ? plan_units.to_f : plan_units
    _plan_units / (user.chargebee_plan_interval[0].to_i * 7)
  end

  def plan_units(plan_interval = "", _meal_type = "", bypass_adjustment = false, adjustment_direction = nil)
    meal = _meal_type.present? ? _meal_type : meal_type

    meal_percentage = meal.split("_")[0].to_i/100.0
    calories_for_meal_per_day = meal_percentage * calories_required

    ounces_for_meal_per_day = (calories_for_meal_per_day/43)

    interval = plan_interval.present? ? plan_interval : user.chargebee_plan_interval

    ounces_for_meal_during_plan_interval = ounces_for_meal_per_day*14 # for 2 weeks

    if interval.include?("4_weeks")
      ounces_for_meal_during_plan_interval = ounces_for_meal_during_plan_interval*2
    end

    if adjustment_direction && adjustment_direction == "higher" && !bypass_adjustment || portion_adjustment.present? && !bypass_adjustment
      plan_daily_serving_rounded = daily_serving(ounces_for_meal_during_plan_interval.floor)
      plan_daily_serving_decimal = daily_serving(ounces_for_meal_during_plan_interval.floor, true)
      plan_daily_serving_difference = plan_daily_serving_decimal-plan_daily_serving_rounded
      plan_daily_serving_higher_decimal = adjusted_daily_serving(plan_daily_serving_rounded, "higher")+plan_daily_serving_difference
      (plan_daily_serving_higher_decimal * (interval[0].to_i * 7)).floor
    else
      ounces_for_meal_during_plan_interval.floor
    end
  end

  def plan_units_v2(total_units = false, bypass_adjustment = false, adjustment_direction = nil)
    total_recipes = [beef_recipe, chicken_recipe, turkey_recipe, lamb_recipe].reject(&:blank?).size

    if !bypass_adjustment && adjustment_direction.nil?
      meal_percentage = cooked_portion / 100.0
    else
      meal_percentage = 100 / 100.0
    end
    calories_for_meal_per_day = meal_percentage * calories_required

    ounces_for_meal_per_day = (calories_for_meal_per_day / 43)

    interval = user.chargebee_plan_interval

    ounces_for_meal_during_plan_interval = ounces_for_meal_per_day*14 # for 2 weeks

    if interval.include?("4_weeks")
      ounces_for_meal_during_plan_interval = ounces_for_meal_during_plan_interval * 2
    end

    if adjustment_direction && adjustment_direction == "higher" && !bypass_adjustment || portion_adjustment.present? && !bypass_adjustment
      plan_daily_serving_rounded = daily_serving(ounces_for_meal_during_plan_interval.floor)
      plan_daily_serving_decimal = daily_serving(ounces_for_meal_during_plan_interval.floor, true)
      plan_daily_serving_difference = plan_daily_serving_decimal-plan_daily_serving_rounded
      plan_daily_serving_higher_decimal = adjusted_daily_serving(plan_daily_serving_rounded, "higher") + plan_daily_serving_difference

      if total_units
        return (plan_daily_serving_higher_decimal * (interval[0].to_i * 7)).floor
      else
        return ((plan_daily_serving_higher_decimal * (interval[0].to_i * 7)) / total_recipes).floor
      end
    end

    total_units ? (ounces_for_meal_during_plan_interval).floor : (ounces_for_meal_during_plan_interval/total_recipes).floor
  end

  def kibble_quantity_v2
    meal_percentage = kibble_portion/100.0
    calories_for_meal_per_day = meal_percentage * calories_required

    # 3300 kcal/kg, chicken, 3300/2.205 = 1497 kcal/lbs, 7485 per 5lbs
    # 3440 kcal/kg, turkey+salmon, 3440/2.205 = 1560 kcal/lbs, 7800 per 5lbs
    # 3570 kcal/kg, duck, 3570/2.205 = 1619 kcal/lbs, 8095 per 5lbs

    if kibble_recipe == "chicken"
      bags_for_meal_per_day = (calories_for_meal_per_day / 7485) # can be a fraction of a bag
    elsif kibble_recipe == "turkey+salmon"
      bags_for_meal_per_day = (calories_for_meal_per_day / 7800) # can be a fraction of a bag
    elsif kibble_recipe == "duck"
      bags_for_meal_per_day = (calories_for_meal_per_day / 8095) # can be a fraction of a bag
    end

    interval = user.chargebee_plan_interval

    ounces_for_meal_during_plan_interval = bags_for_meal_per_day*14 # for 2 weeks

    if interval.include?("4_weeks")
      ounces_for_meal_during_plan_interval = ounces_for_meal_during_plan_interval*2
    end

    ounces_for_meal_during_plan_interval.ceil # rounded up to the next amount of bags
  end

  def adjusted_daily_serving(plan_daily_serving, direction = nil)
    case plan_daily_serving
    when 0..2
      adjusted_plan_daily_serving = direction == "higher" ? 4 : 2
    when 3..5
      adjusted_plan_daily_serving = direction == "higher" ? 6 : 4
    else
      if plan_daily_serving.odd?
        adjusted_plan_daily_serving = direction == "higher" ? plan_daily_serving + 1 : plan_daily_serving - 1
      else
        adjusted_plan_daily_serving = direction == "higher" ? plan_daily_serving + 2 : plan_daily_serving
      end
    end

    adjusted_plan_daily_serving
  end

  def price_estimate(meal_params = {})
    temp_dog_attr = dup.attributes
    temp_dog_attr[:beef_recipe] = meal_params[:beef_recipe]
    temp_dog_attr[:lamb_recipe] = meal_params[:lamb_recipe]
    temp_dog_attr[:chicken_recipe] = meal_params[:chicken_recipe]
    temp_dog_attr[:turkey_recipe] = meal_params[:turkey_recipe]
    temp_dog_attr[:kibble_recipe] = meal_params[:kibble_recipe]
    temp_dog_attr[:cooked_portion] = meal_params[:cooked_portion]
    temp_dog_attr[:kibble_portion] = meal_params[:kibble_portion]
    temp_dog_attr[:portion_adjustment] = meal_params[:portion_adjustment]
    temp_dog_attr[:created_at] = user.created_at

    temp_dog = Dog.new(temp_dog_attr)

    subscription_param_addons = []

    subscription_param_addons.push({
      id: "beef_#{user.chargebee_plan_interval}",
      unit_price: user.unit_price("beef_#{user.chargebee_plan_interval}"),
      quantity: temp_dog.plan_units_v2
    }) if temp_dog.beef_recipe

    subscription_param_addons.push({
      id: "chicken_#{user.chargebee_plan_interval}",
      unit_price: user.unit_price("chicken_#{user.chargebee_plan_interval}"),
      quantity: temp_dog.plan_units_v2
    }) if temp_dog.chicken_recipe

    subscription_param_addons.push({
      id: "turkey_#{user.chargebee_plan_interval}",
      unit_price: user.unit_price("turkey_#{user.chargebee_plan_interval}"),
      quantity: temp_dog.plan_units_v2
    }) if temp_dog.turkey_recipe

    subscription_param_addons.push({
      id: "lamb_#{user.chargebee_plan_interval}",
      unit_price: user.unit_price("lamb_#{user.chargebee_plan_interval}"),
      quantity: temp_dog.plan_units_v2
    }) if temp_dog.lamb_recipe

    subscription_param_addons.push({
      id: "#{temp_dog.kibble_recipe}_kibble_#{user.chargebee_plan_interval}",
      quantity: temp_dog.kibble_quantity_v2
    }) if temp_dog.kibble_recipe.present?

    # Include service fee
    if user.dogs.size == 1 && temp_dog.only_cooked_recipe && temp_dog.plan_units_v2(true) < user.plan_unit_fee_limit && user.created_at < DateTime.parse("November 5, 2020 at 7:40am EDT")
      subscription_param_addons.push(
        {
          id: "delivery-service-fee-#{user.how_often.split("_")[0]}-weeks"
        }
      )
    end

    result = ChargeBee::Estimate.update_subscription({
      subscription: {
        id: chargebee_subscription_id,
        plan_id: user.chargebee_plan_interval,
        use_existing_balances: false
      },
      addons: subscription_param_addons,
      replace_addon_list: true
    })

    invoice_estimate = result.estimate.next_invoice_estimate

    if !temp_dog.beef_recipe && !temp_dog.chicken_recipe && !temp_dog.turkey_recipe && !temp_dog.lamb_recipe && temp_dog.kibble_recipe.blank?
      "--"
    else
      "#{Money.new(invoice_estimate.total).format}"
    end
  rescue StandardError => e
    puts "Error: #{e.message}"
  end

  def daily_price_estimate
    # Estimate without taxes, with discount
    result = ChargeBee::Estimate.create_subscription({
      subscription: {
        plan_id: "25_beef_2_weeks",
        plan_quantity: MyLib::Home.plan_units("2_weeks", "25_beef", calories_required)
      },
    })
    invoice_estimate = result.estimate.invoice_estimate
    beef_25_daily = "#{Money.new(invoice_estimate.total/14).format}/day"


    result = ChargeBee::Estimate.create_subscription({
      subscription: {
        plan_id: "100_beef_2_weeks",
        plan_quantity: MyLib::Home.plan_units("2_weeks", "100_beef", calories_required)
      },
    })
    invoice_estimate = result.estimate.invoice_estimate
    beef_100_daily = "#{Money.new(invoice_estimate.total/14).format}/day"

    { beef_25_daily: beef_25_daily, beef_100_daily: beef_100_daily }
  end

  def weekly_price_estimate(recipe, portion) # referral_code = "40off"
    if true # !referral_code
      # Estimate without taxes, without discount
      result = ChargeBee::Estimate.create_subscription({
        subscription: {
          plan_id: "#{portion}_#{recipe}_2_weeks",
          plan_quantity: MyLib::Home.plan_units("2_weeks", "#{portion}_#{recipe}", calories_required)
        }
      })
      invoice_estimate = result.estimate.invoice_estimate
      no_discount_weekly = "#{Money.new(invoice_estimate.total/2).format}/week"
    else
      referral_code_check = MyLib::Referral.check_code(referral_code)
      # Estimate without taxes, with discount
      result = ChargeBee::Estimate.create_subscription({
        subscription: {
          plan_id: "#{portion}_#{recipe}_2_weeks",
          plan_quantity: MyLib::Home.plan_units("2_weeks", "#{portion}_#{recipe}", calories_required)
        },
        coupon_ids: [referral_code_check ? referral_code : "40off"],
      })
      invoice_estimate = result.estimate.invoice_estimate
      discount_weekly = "#{Money.new(invoice_estimate.total/2).format}/week"
    end

    { no_discount_weekly: no_discount_weekly, discount_weekly: discount_weekly }
  end

  def readable_body_type
    case body_type
    when 0 then "skinny"
    when 1 then "ideal"
    when 2 then "rounded"
    when 3 then "chunky"
    end
  end

  def readable_neutered
    neutered ? "#{gender == Constants::FEMALE ? "spayed" : "neutered"}" : "not #{gender == Constants::FEMALE ? "spayed" : "neutered"}"
  end

  def readable_activity_level
    case activity_level
    when 0 then "lazy"
    when 1 then "ideal"
    when 2 then "very active"
    end
  end

  def indefinite_articlerize(params_word)
    %w(a e i o u).include?(params_word[0].downcase) ? "an #{params_word}" : "a #{params_word}"
  end

  def description
    # TODO: Removed allergies from here since we're not tracking it in the onboarding
    # TODO: Update age from months to year when back in use
    "#{gender_pronoun.capitalize} is
      #{age_in_months < 12 ? "less than one year" : "#{age_in_months} #{'months'.pluralize(age_in_months)}"} old,
      #{weight} #{weight_unit}, and
      #{readable_neutered}.
      #{gender_pronoun(true).capitalize} body size is #{readable_body_type} and
      #{gender_pronoun(true)} activity level is #{readable_activity_level}.
      #{gender_pronoun.capitalize} is #{indefinite_articlerize(breed)}.
    "
  end

  def meal_type_options
    if topper_available
      [["Beef (25% portion)", "25_beef"], ["Beef (100% portion)", "100_beef"], ["Chicken (25% portion)", "25_chicken"], ["Chicken (100% portion)", "100_chicken"], ["Beef & Chicken (25% portion)", "25_beef+chicken"], ["Beef & Chicken (100% portion)", "100_beef+chicken"]]
    else
      [["Beef (100% portion)", "100_beef"], ["Chicken (100% portion)", "100_chicken"], ["Beef + Chicken (100% portion)", "100_beef+chicken"]]
    end
  end

  # Recurring Addons
  def subscription_recurring_addon(recipe_type, chargebee_plan_interval, quantity)
    addon_id = "#{recipe_type}_#{chargebee_plan_interval}"
    {
      id: addon_id,
      unit_price: user.unit_price(addon_id),
      quantity: quantity
    }
  end

  # Onboarding data
  class << self
    # Get breed list
    def breeds
      Breed.find_each.reject { |breed| breed.name&.downcase == "unknown" }.map { |breed|
        { label: breed.name, value: breed.id }
      }
    end

    # Get age list
    def ages
      Constants::AGE_OPTIONS.map { |age|
        { label: age[0], value: age[1] }
      }
    end

    # Get genders
    def genders
      ["Female", "Male"].map { |gender|
        { label: gender, value: gender == "Male" }
      }
    end

    # Get weight unit list
    def weight_units
      [ 0, "lbs", "kg" ].map { |unit|
        { label: unit, value: unit }
      }
    end

    # Get body types
    def body_types
      Constants::BODY_TYPES.each_with_index.map { |type, index|
        { label: type, value: index }
      }
    end

    # Get activity levels
    def activity_levels
      Constants::ACTIVITY_LEVELS.each_with_index.map { |type, index|
        { label: type, value: index }
      }
    end
  end
end
