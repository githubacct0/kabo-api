# frozen_string_literal: true

class AirtableWorker
  include Sidekiq::Worker
  sidekiq_options queue: :airtable

  def perform(params = {})
    airtable_tt_purchase = Airrecord.table(Rails.configuration.airtable[:api_key], params["table_id"], params["view_name"])
    airtable_tt_purchase.create(params["record"])
  end
end
