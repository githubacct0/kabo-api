# frozen_string_literal: true

class TempDog < ApplicationRecord
  include Dogable

  # Relations
  belongs_to :temp_user

  serialize :food_restriction_items, JSON

  before_update :update_portion_and_recipe

  def update_portion_and_recipe
    if meal_type.present?
      meal_type = meal_type.split("_")
      self.portion, self.recipe = meal_type
    end
  end

  def has_food_restriction
    if food_restriction_items.any? && food_restriction
      (food_restriction_items & ["beef", "fish"]).any?
    else false
    end
  end

  def portions
    [cooked_portion, kibble_portion].reject(&:blank?)
  end
end
