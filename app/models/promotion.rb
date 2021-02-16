# frozen_string_literal: true

class Promotion < ApplicationRecord
  has_and_belongs_to_many :users
end
