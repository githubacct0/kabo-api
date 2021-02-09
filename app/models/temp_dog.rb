# frozen_string_literal: true

class TempDog < ApplicationRecord
  include Dogable

  # Relations
  belongs_to :temp_user
  belongs_to :user, class_name: "TempUser", foreign_key: "temp_user_id"

  serialize :food_restriction_items, JSON

  before_update :update_portion_and_recipe

  def update_portion_and_recipe
    if meal_type.present?
      meal_type = meal_type.split("_")
      self.portion, self.recipe = meal_type
    end
  end

  def portions
    [cooked_portion, kibble_portion].reject(&:blank?)
  end
end
