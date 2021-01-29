# frozen_string_literal: true

class KlaviyoWorker
  include Sidekiq::Worker
  sidekiq_options queue: :klaviyo

  def perform(params = {})
    RestClient.post "https://a.klaviyo.com/api/v2/list/#{params['list_id']}/subscribe",
      {
        api_key: "pk_344ea398d7d3cfb0570c6d7e6763bdc5b7",
        "profiles": [
          {
            "email": params["email"]
          }
        ]
      }.to_json, { content_type: :json, accept: :json }
  end
end
