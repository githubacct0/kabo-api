# frozen_string_literal: true

module MyLib
  class Paypal
    class << self
      def create_billing_agreement(token:)
        RestClient.post Rails.configuration.paypal_api[:url],
          {
            USER: Rails.configuration.paypal_api[:user],
            PWD: Rails.configuration.paypal_api[:password],
            SIGNATURE: Rails.configuration.paypal_api[:signature],
            METHOD: "CreateBillingAgreement",
            VERSION: 86,
            TOKEN: token
          }
      end

      def get_express_checkout_details(token:)
        RestClient.post Rails.configuration.paypal_api[:url],
          {
            USER: Rails.configuration.paypal_api[:user],
            PWD: Rails.configuration.paypal_api[:password],
            SIGNATURE: Rails.configuration.paypal_api[:signature],
            METHOD: "GetExpressCheckoutDetails",
            VERSION: 86,
            TOKEN: token
          }
      end
    end
  end
end
