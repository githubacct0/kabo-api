# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user

  enum category: [ :general, :delivery ]
  enum action: [:none, :view_settings, :unpause, :reactivate, :track_delivery]
end
