# frozen_string_literal: true

class Chargebee::RemoveUnbilledChargesFromSubscriptionWorker
  include Sidekiq::Worker
  sidekiq_options queue: :chargebee_remove_unbilled_charges_from_subscription

  def perform(params = {})
    ChargeBee::UnbilledCharge.list({
      "subscription_id[is]": params["subscription_id"]
    }).each do |entry|
      ChargeBee::UnbilledCharge.delete(entry.unbilled_charge.id)
    end
  end
end
