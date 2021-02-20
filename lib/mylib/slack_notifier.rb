# frozen_string_literal: true

module MyLib
  class SlackNotifier
    class << self
      def notify(notifier: nil, webhook: nil, text:, icon_emoji:)
        if Rails.env.production?
          begin
            notifier ||= Slack::Notifier.new webhook
            notifier.post(
              text: text,
              icon_emoji: icon_emoji
            )
          rescue StandardError => e
            Raven.capture_exception(e)
          end
        end
      end
    end
  end
end
