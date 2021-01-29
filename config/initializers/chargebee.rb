ChargeBee.configure({
  api_key: Rails.configuration.chargebee[:api_key],
  site: Rails.configuration.chargebee[:site]
})
