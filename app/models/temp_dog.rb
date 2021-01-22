# frozen_string_literal: true

class TempDog < ApplicationRecord
  # Relations
  belongs_to :temp_user
  belongs_to :main_breed, class_name: "Breed", optional: true
  belongs_to :secondary_breed, class_name: "Breed", optional: true
end
