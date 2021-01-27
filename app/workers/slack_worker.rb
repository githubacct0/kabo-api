# frozen_string_literal: true

class SlackWorker
  include Sidekiq::Worker
  sidekiq_options queue: :slack

  def perform(params = {})
    notifier = Slack::Notifier.new params["hook_url"]

    post_params = {
      text: params["text"]
    }

    post_params[:attachments] = [params["user_info"]] if params["user_info"].present?
    post_params[:icon_emoji] = params["icon_emoji"] if params["icon_emoji"].present?

    notifier.post(post_params)
  end
end
