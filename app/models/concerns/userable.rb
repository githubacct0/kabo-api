# frozen_string_literal: true

module Userable
  extend ActiveSupport::Concern

  def unit_price(sku)
    if created_at < DateTime.parse("Aug 25, 2020 at 10pm EDT") # Date of deploy, updating to 0.60/oz
      sku.include?("lamb") ? 75 : 50
    else
      sku.include?("lamb") ? 75 : 60
    end
  end

  def plan_unit_fee_limit
    created_at > DateTime.parse("June 11, 2020 at 11pm EDT") ? 56 : 40
  end

  # Get how often value
  def how_often
    plan_split = chargebee_plan_interval.split("_")
    if plan_split.size == 2 then "#{plan_split[0]}_week-delay"
    elsif plan_split[3] == "week-delay" then "#{plan_split[2]}_week-delay"
    end
  end

  def how_often_options
    if trial_length == 4
      [
        ["every 4 weeks", "4_week-delay"],
        ["every 6 weeks", "6_week-delay"],
        ["every 8 weeks", "8_week-delay"],
        ["every 12 weeks (3 months)", "12_week-delay"],
        ["every 26 weeks (6 months)", "26_week-delay"]
      ].map { |option| { label: option[0], value: option[1] } }
    else
      [
        ["every 2 weeks", "2_week-delay"],
        ["every 4 weeks", "4_week-delay"],
        ["every 6 weeks", "6_week-delay"],
        ["every 8 weeks", "8_week-delay"],
        ["every 12 weeks (3 months)", "12_week-delay"],
        ["every 26 weeks (6 months)", "26_week-delay"]
      ].map { |option| { label: option[0], value: option[1] } }
    end
  end

  # Get id of dog of subscription
  def subscription_dog_id(subscription_id:)
    dogs.find { |dog| dog.chargebee_subscription_id == subscription_id }&.id
  end

  class_methods do
    REGEX_PATTERN = /^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$/
    def is_email_valid?(email)
      REGEX_PATTERN.match?(email)
    end
  end
end
