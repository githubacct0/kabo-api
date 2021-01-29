# frozen_string_literal: true

class FacebookWorker
  include Sidekiq::Worker
  sidekiq_options queue: :facebook

  def perform(params)
    amounts_paid = []

    User.find(params["user_id"]).dogs.each do |dog|
      transactions = ChargeBee::Transaction.list({
        "type[in]": "['payment']",
        "subscription_id[is]": dog.chargebee_subscription_id,
        "sort_by[asc]": "date",
        "limit": 1
      })

      amounts_paid.push(transactions.first.transaction.amount)
    end

    total_paid = Money.new(amounts_paid.sum).to_f

    FacebookAds.configure do |config|
      config.access_token = Rails.configuration.facebook_access_token
    end

    user_data = FacebookAds::ServerSide::UserData.new(
      email: params["email"],
      fbc: params["fbc"],
      fbp: params["fbp"])

    custom_data = FacebookAds::ServerSide::CustomData.new(
      currency: "cad",
      value: total_paid)

    event = FacebookAds::ServerSide::Event.new(
      event_name: "Purchase",
      event_time: Time.now.to_i,
      user_data: user_data,
      custom_data: custom_data)


    request = FacebookAds::ServerSide::EventRequest.new(
      pixel_id: "382791969157517",
      events: [event])

    request.execute
  end
end
