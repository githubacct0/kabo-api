# frozen_string_literal: true

module Dogable
  extend ActiveSupport::Concern

  included do
    belongs_to :main_breed, class_name: "Breed", optional: true
    belongs_to :secondary_breed, class_name: "Breed", optional: true

    enum gender: [ :female, :male ]
    enum weight_unit: [ :lbs, :kg ]
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
    kibble_recipe.present? && [beef_recipe, chicken_recipe, lamb_recipe, turkey_recipe].reject(&:blank?).size >= 1
  end

  def only_kibble_recipe
    [beef_recipe, chicken_recipe, turkey_recipe, lamb_recipe].reject(&:blank?).empty?
  end

  def reached_recipe_limit
    [beef_recipe, chicken_recipe, lamb_recipe, turkey_recipe, kibble_recipe].reject(&:blank?).size == 2
  end

  def recipes
    [beef_recipe, chicken_recipe, lamb_recipe, turkey_recipe, kibble_recipe].reject(&:blank?)
  end

  def topper_available
    !(weight_unit == "lbs" && weight <= 9) && !(weight_unit == "kg" && weight <= 4)
  end
end
