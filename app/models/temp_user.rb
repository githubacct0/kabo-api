# frozen_string_literal: true

class TempUser < ApplicationRecord
  include Userable

  # Relations
  has_many :temp_dogs, inverse_of: :temp_user
  has_many :dogs, class_name: "TempDogs", foreign_key: "temp_dog_id"

  accepts_nested_attributes_for :temp_dogs, reject_if: :all_blank, allow_destroy: true

  validates_associated :temp_dogs, message: "profile is incomplete"

  def calculated_trial_length
    temp_dogs.size == 1 && !temp_dogs.first.topper_available ? 4 : 2
  end

  def temp_dog_ids
    temp_dogs.map { |temp_dog| temp_dog.id }
  end
end
