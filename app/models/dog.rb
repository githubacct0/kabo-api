# frozen_string_literal: true

class Dog < ApplicationRecord
  # Relations
  belongs_to :user
  belongs_to :main_breed, class_name: "Breed", optional: true
  belongs_to :secondary_breed, class_name: "Breed", optional: true
end
