# frozen_string_literal: true

class CancelledSubscriptionsWorker
  include Sidekiq::Worker
  sidekiq_options queue: :cancelled_subscription, retry: false

  def perform(user_email)
    export_csv = ExportHelper.cancelled_subscriptions

    temp_file = Tempfile.open("export-", Rails.root.join("tmp")) do |f|
      f.print(export_csv)
      f.flush
    end

    mg_client = Mailgun::Client.new(Rails.configuration.mailgun_api_key)
    mb_obj = Mailgun::MessageBuilder.new

    mb_obj.from(Rails.configuration.emails[:help])

    mb_obj.add_recipient(:to, user_email)

    mb_obj.subject("Kabo Cancelled Subscriptions Export - #{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}")

    mb_obj.body_text("Cancelled Subscriptions Export is attached")

    mb_obj.add_attachment(temp_file.path, "cancelled-subscriptions-export-#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.csv")

    mg_client.send_message("mg.kabo.co", mb_obj)
  end
end
