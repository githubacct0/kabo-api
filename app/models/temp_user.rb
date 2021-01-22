# frozen_string_literal: true

class TempUser < ApplicationRecord
  # Relations
  has_many :temp_dogs, inverse_of: :temp_user
end
