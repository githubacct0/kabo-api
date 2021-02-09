# frozen_string_literal: true

module MyLib
  class Referral
    class << self
      def check_code(code)
        return false if code.nil?

        begin
          result = Rails.cache.fetch("chargebee/coupon/#{code}", expires_in: 30.minutes) do
            ChargeBee::Coupon.retrieve(code)
          end
          result.coupon.status != "active" ? false : "#{result.coupon.discount_percentage.to_i}%"
        rescue Exception => err
          puts "app_log(ERROR: referral code check): #{err.message}"
          false
        end
      end
    end
  end
end
