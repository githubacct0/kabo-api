# frozen_string_literal: true

module Dogable
  extend ActiveSupport::Concern

  included do
    belongs_to :main_breed, class_name: "Breed", optional: true
    belongs_to :secondary_breed, class_name: "Breed", optional: true

    enum gender: [ :female, :male ]
    enum weight_unit: [ :lbs, :kg ]
  end

  class_methods do
    # Get cooked recipes
    def cooked_recipes
      [
        "Tender Chicken",
        "Savoury Beef",
        "Hearty Turkey",
        "Luscious Lamb"
      ].map { |name| get_recipe_details(name: name) }
    end

    # Get kibble recipes
    def kibble_recipes
      [
        "Chicken",
        "Turkey & Salmon",
        "Duck"
      ].map { |name| get_recipe_details(name: name) }
    end

    def get_recipe_details(name:)
      kibble_image_url = Rails.configuration.recipe_images[:kibble]
      case name
      when "Tender Chicken"
        {
          name: "Tender Chicken",
          recipe: "chicken",
          image_url: Rails.configuration.recipe_images[:chicken],
          description: "A lean protein diet with hearty grains. Made with Canadian-sourced chicken.",
          new: false,
          analysis: Constants::CHICKEN_ANALYSIS,
          ingredients: Constants::CHICKEN_RECIPE
        }
      when "Savoury Beef"
        {
          name: "Savoury Beef",
          recipe: "beef",
          image_url: Rails.configuration.recipe_images[:beef],
          description: "A grain-free diet, perfect for picky eaters! Made from locally-sourced beef.",
          new: false,
          analysis: Constants::BEEF_ANALYSIS,
          ingredients: Constants::BEEF_RECIPE
        }
      when "Hearty Turkey"
        {
          name: "Hearty Turkey",
          recipe: "turkey",
          image_url: Rails.configuration.recipe_images[:turkey],
          description: "Made with lean, locally-sourced turkey breast. Low-Fat. Gluten-Free.",
          new: false,
          analysis: Constants::TURKEY_ANALYSIS,
          ingredients: Constants::TURKEY_RECIPE
        }
      when "Luscious Lamb"
        {
          name: "Luscious Lamb",
          recipe: "lamb",
          image_url: Rails.configuration.recipe_images[:lamb],
          description: "Made with premium Ontario lamb. A novel protein choice for picky eaters and senior dogs!",
          new: true,
          analysis: Constants::LAMB_ANALYSIS,
          ingredients: Constants::LAMB_RECIPE
        }
      when "Chicken"
        {
          name: "Chicken",
          recipe: "chicken",
          image_url: kibble_image_url,
          description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
          new: false,
          analysis: Constants::CHICKEN_KIBBLE_ANALYSIS,
          ingredients: Constants::CHICKEN_KIBBLE_RECIPE
        }
      when "Turkey & Salmon"
        {
          name: "Turkey & Salmon",
          recipe: "turkey+salmon",
          image_url: kibble_image_url,
          description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
          new: false,
          analysis: Constants::TURKEY_SALMON_KIBBLE_ANALYSIS,
          ingredients: Constants::TURKEY_SALMON_KIBBLE_RECIPE
        }
      when "Duck"
        {
          name: "Duck",
          recipe: "duck",
          image_url: kibble_image_url,
          description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
          new: false,
          analysis: Constants::DUCK_KIBBLE_ANALYSIS,
          ingredients: Constants::DUCK_KIBBLE_RECIPE
        }
      else {}
      end
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

  def readable_meal_type
    case meal_type
    when "25_beef" then "Beef, 25% Topper"
    when "100_beef" then "Beef, 100% Full Meal"
    when "25_chicken" then "Chicken, 25% Topper"
    when "100_chicken" then "Chicken, 100% Full Meal"
    when "25_lamb" then "Lamb, 25% Topper"
    when "100_lamb" then "Lamb, 100% Full Meal"
    end
  end

  def readable_recipe
    case meal_type.split("_")[1]
    when "beef" then "Savoury Beef"
    when "chicken" then "Tender Chicken"
    when "lamb" then "Luscious Lamb"
    when "beef+chicken" then "Variety Pack"
    end
  end

  def readable_cooked_recipes
    recipes = []
    recipes.push("Chicken") if chicken_recipe
    recipes.push("Beef") if beef_recipe
    recipes.push("Turkey") if turkey_recipe
    recipes.push("Lamb") if lamb_recipe
    return nil if recipes.empty?
    recipes.join(", ")
  end

  def readable_kibble_recipe
    case kibble_recipe
    when "chicken" then "Chicken"
    when "turkey+salmon" then "Turkey & Salmon"
    when "duck" then "Duck"
    else nil
    end
  end

  def readable_mealplan
    recipes = []
    recipes.push("Tender Chicken") if chicken_recipe
    recipes.push("Savoury Beef") if beef_recipe
    recipes.push("Luscious Lamb") if lamb_recipe
    recipes.push("Hearty Turkey") if turkey_recipe
    recipes.push("Chicken Recipe") if kibble_recipe == "chicken"
    recipes.push("Turkey & Salmon") if kibble_recipe == "turkey+salmon"
    recipes.push("Duck") if kibble_recipe == "duck"

    "#{user.chargebee_plan_interval[0]} weeks of #{recipes.join(', ')}"
  end

  def readable_portion_v2
    portions = []
    portions.push("#{cooked_portion}% cooked") if cooked_portion.present?
    portions.push("#{kibble_portion}% kibble") if kibble_portion.present?

    portions.join(", ")
  end

  def readable_portion
    case meal_type.split("_")[0]
    when "25" then "topper"
    when "100" then "full-meal"
    end
  end

  def calories_required
    dog_weight = weight

    if weight_unit == Constants::LBS
      dog_weight = dog_weight / 2.2046
    end

    rer = (dog_weight ** 0.75) * 70

    if created_at > DateTime.parse("June 30, 2020 at 1:20am EDT") # Date of deploy, updating calorie calculation
      case age_in_months
      when 0 then (rer * 4.0).round
      when 1 then (rer * 3.5).round
      when 4 then (rer * 2.5).round
      when 2 then (rer * 1.75).round
      else (rer * 1.5).round
      end
    else
      if age_in_months < 12 then (rer * 2.0).round
      elsif activity_level == 2 then (rer * 1.4).round
      else (rer * 1.25).round
      end
    end
  end

  def gender_pronoun(alt = false)
    case gender
    when Constants::FEMALE then alt ? "her" : "she"
    when Constants::MALE then alt ? "his" : "he"
    end
  end

  def has_food_restriction
    if food_restriction_items.any? && food_restriction
      (food_restriction_items & ["beef", "fish"]).any?
    else false
    end
  end

  def has_possible_food_restriction # TODO: Update for multiple recipes if adding food restriction question back to signup
    ingredients_list = [
      "Ground Beef",
      "Beef Liver",
      "Russet Potato",
      "Sweet Potato",
      "Carrot",
      "Green Beans",
      "Green Peas",
      "Apples",
      "Safflower oil",
      "Omega Plus Fish Oil",
      "beef", # ALTERNATIVE MATCHES BELOW
      "liver",
      "sweet",
      "potato",
      "beans",
      "peas",
      "safflower",
      "omega",
      "oil"
    ]

    return true if !food_restriction_custom.nil? && ingredients_list.any? { |word| food_restriction_custom.downcase.include?(word.downcase) }

    false
  end

  def only_cooked_recipe
    kibble_recipe.blank?
  end

  def mixed_cooked_and_kibble_recipe
    kibble_recipe.present? && [beef_recipe, chicken_recipe, lamb_recipe, turkey_recipe].count(true) >= 1
  end

  def only_kibble_recipe
    [beef_recipe, chicken_recipe, turkey_recipe, lamb_recipe].count(true) == 0
  end

  def reached_recipe_limit
    [beef_recipe, chicken_recipe, lamb_recipe, turkey_recipe, kibble_recipe].reject(&:blank?).size == 2
  end

  def recipes
    [beef_recipe, chicken_recipe, lamb_recipe, turkey_recipe, kibble_recipe].reject(&:blank?)
  end

  def topper_available
    (weight_unit == "lbs" && weight > 9) || (weight_unit == "kg" && weight > 4)
  end

  # Get daily portions
  def daily_portions(type:)
    portions = []
    if only_cooked_recipe
      portions = only_cooked_recipe_daily_portions(type: type)
    elsif mixed_cooked_and_kibble_recipe
      portions = mixed_cooked_and_kibble_recipe_daily_portions
    elsif only_kibble_recipe
      portions = only_kibble_recipe_daily_portions
    end

    portions
  end

  # Get price estimate
  def price_estimate(meal_params = {})
    temp_dog_attr = self.dup.attributes
    temp_dog_attr.merge!(meal_params)
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

  # Recurring Addon
  def subscription_recurring_addon(recipe_type, chargebee_plan_interval, quantity)
    addon_id = "#{recipe_type}_#{chargebee_plan_interval}"
    {
      id: addon_id,
      unit_price: user.unit_price(addon_id),
      quantity: quantity
    }
  end

  # Get subscription param addons
  def subscription_param_addons
    addons = []

    # add addon for lower AOV customers, only if the customer has 1 dog
    if user.dogs.size == 1 && kibble_portion.blank? && plan_units_v2(true) < user.plan_unit_fee_limit
      addons.push({ id: "delivery-service-fee-#{user.how_often.split("_")[0]}-weeks" })
    end

    # RECURRING ADDONS
    user_chargebee_plan_interval = user.chargebee_plan_interval
    beef_recipe && addons.push(subscription_recurring_addon("beef", user_chargebee_plan_interval, dog_plan_units_v2))
    chicken_recipe && addons.push(subscription_recurring_addon("chicken", user_chargebee_plan_interval, dog_plan_units_v2))
    turkey_recipe && addons.push(subscription_recurring_addon("turkey", user_chargebee_plan_interval, dog_plan_units_v2))
    lamb_recipe && addons.push(subscription_recurring_addon("lamb", user_chargebee_plan_interval, dog_plan_units_v2))

    kibble_recipe.present? && addons.push({
      id: "#{kibble_recipe}_kibble_#{user_chargebee_plan_interval}",
      quantity: kibble_quantity_v2
    })

    addons
  end

  # Get only cooked recipe daily portions
  def only_cooked_recipe_daily_portions(type:)
    portions = [
      {
        title: "25% Kabo Diet",
        description: "About 25% of #{name}'s daily caloric needs. Mix it in with their current food to give them the nutrients of fresh food at a more affordable price point!",
        cooked_portion: 25,
        portion_adjustment: nil
      },
      {
        title: "100% Kabo Diet",
        description: "A complete and balanced diet for #{name}. You will receive enough food for 100% of #{name}'s daily caloric needs, which is 1091 calories.",
        cooked_portion: 100,
        portion_adjustment: nil
      }
    ]
    case type
    when "onboarding" then portions
    when "frontend"
      higher_percent = (((plan_units_v2(true, false, "higher") - plan_units_v2(true, true)).to_f / plan_units_v2(true, true)).abs * 100).floor
      percent = 25 + higher_percent
      if percent < 100
        portions.insert(1, {
          title: "#{percent}% Kabo Diet",
          description: "For those who want a little more Kabo to their food",
          cooked_portion: 25,
          portion_adjustment: "higher"
        })

        portions << {
          title: "Full Kabo Diet + #{higher_percent}% More",
          description: "For dogs who need to gain back to a healthy weight",
          cooked_portion: 100,
          portion_adjustment: "higher"
        }
      end
    else []
    end
  end

  # Get mixed cooked and kibble recipe daily portions
  def mixed_cooked_and_kibble_recipe_daily_portions
    [
      {
        title: "25% cooked, 75% kibble",
        cooked_portion: 25,
        kibble_portion: 75
      },
      {
        title: "50% cooked, 50% kibble",
        cooked_portion: 50,
        kibble_portion: 50
      }
    ]
  end

  # Get only kibble recipe daily portions
  def only_kibble_recipe_daily_portions
    [
      {
        title: "2 weeks worth",
        description: "You'll get enough kibble for #{name} to last 2 weeks. Feeding instructions will be provided.",
        kibble_portion: 100,
        plan_interval: 2
      }
    ]
  end
end
