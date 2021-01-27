# frozen_string_literal: true

class FoodBrand < ApplicationRecord
  enum food_type: [ :dry, :wet, :other ]
end
