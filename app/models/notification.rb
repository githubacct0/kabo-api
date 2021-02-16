# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user

  enum category: [ :general, :delivery ]
  enum action: [:no_action, :view_settings, :unpause, :reactivate, :track_delivery]
end
