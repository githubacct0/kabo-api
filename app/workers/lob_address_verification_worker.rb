# frozen_string_literal: true

class LobAddressVerificationWorker
  include Sidekiq::Worker
  sidekiq_options queue: :lob_address_verification

  def perform(user)
    lob = Lob::Client.new(api_key: Rails.configuration[:lob_api_private_key])

    lob_response = lob.intl_verifications.verify(
      primary_line: user["shipping_street_address"],
      secondary_line: user["shipping_apt_suite"],
      city: user["shipping_city"],
      state: user["shipping_province"],
      postal_code: user["shipping_postal_code"],
      country: "CA"
    )

    if lob_response["deliverability"] != "deliverable"
      AirtableWorker.perform_async(
        table_id: Rails.configuration.airtable[:app_key],
        view_name: "Customers",
        record: {
          "Email": user["email"],
          "CB Customer ID": user["chargebee_customer_id"],
          "Status": lob_response["deliverability"]
        }
      )
    end
  end
end
