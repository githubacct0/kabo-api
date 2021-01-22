# frozen_string_literal: true

module MyLib
  class Referral
    class << self
      def check_code(code)
        result = Rails.cache.fetch("chargebee/coupon/#{code}", expires_in: 30.minutes) do
          ChargeBee::Coupon.retrieve(code)
        end
        return false if result.coupon.status != "active"
        "#{result.coupon.discount_percentage.to_i}%"
      rescue Exception => err
        puts "Error: #{err.message}"
        false
      end
    end
  end
end
