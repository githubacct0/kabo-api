# frozen_string_literal: true

class ExportWorker
  include Sidekiq::Worker
  sidekiq_options queue: :export, retry: false

  def perform(type, user_email, from = nil, to = nil)
    export_csv = case type
                 when "recurring" then MyLib::Export.orders_for_production_and_shipping(from, to)
                 when "one-time-purchase" then MyLib::Export.orders_for_production_and_shipping_one_time_purchase
    end

    temp_file = Tempfile.open("export-", Rails.root.join("tmp")) do |f|
      f.print(export_csv)
      f.flush
    end

    # Upload to ops export archive
    storage = Google::Cloud::Storage.new
    bucket = storage.bucket("kabo-ops")
    bucket.create_file(temp_file.path, "orders-combined-production-shipping-#{type}-export-#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.csv")

    # Send email with export attached
    mg_client = Mailgun::Client.new(Rails.configuration.mailgun_api_key)
    mb_obj = Mailgun::MessageBuilder.new
    mb_obj.from(Rails.configuration.emails[:help])
    mb_obj.add_recipient(:to, user_email)
    mb_obj.subject("Kabo Export (#{type}) - #{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}")
    mb_obj.body_text("Export is attached")
    mb_obj.add_attachment(temp_file.path, "orders-combined-production-shipping-#{type}-export-#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.csv")
    mg_client.send_message("mg.kabo.co", mb_obj)
  end
end
