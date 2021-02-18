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

  # Onboarding data
  class << self
    # Get breed list
    def breeds
      _breeds = []
      Breed.where.not("lower(name) LIKE ?", "%unknown%").find_each do |breed|
        _breeds << { label: breed.name, value: breed.id }
      end

      _breeds
    end

    # Get unknown breed list
    def unknown_breeds
      _unknown_breeds = []
      Breed.where("lower(name) LIKE ?", "%unknown%").find_each do |breed|
        _unknown_breeds << { label: breed.name, value: breed.id }
      end

      _unknown_breeds
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
