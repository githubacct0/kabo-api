# frozen_string_literal: true

class Activity < ApplicationRecord
  enum kind: [ :meal_plan, :address ]
end
