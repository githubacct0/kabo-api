require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module KaboApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.chargebee = {
      api_key: ENV.fetch("CHARGEBEE_API_KEY", ""),
      site: ENV.fetch("CHARGEBEE_SITE", "")
    }
    config.google_api = {
      private_key: ENV.fetch("GOOGLE_API_PRIVATE_KEY", ""),
      public_key: ENV.fetch("GOOGLE_API_PUBLIC_KEY", "")
    }
    config.lob_api_private_key = ENV.fetch("LOB_API_PRIVATE_KEY", "")
    config.mailgun_api_key = ENV.fetch("MAILGUN_API_KEY", "")
    config.paypal_api = {
      password: ENV.fetch("PAYPAL_API_PWD", ""),
      signature: ENV.fetch("PAYPAL_API_SIGNATURE", ""),
      url: ENV.fetch("PAYPAL_API_URL", ""),
      user: ENV.fetch("PAYPAL_API_USER", "")
    }
    config.stripe_publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", "")
    config.heroku_app_name = ENV.fetch("HEROKU_APP_NAME", "")
    config.klaviyo_api_key = ENV.fetch("KLAVIYO_API_KEY", "")
    config.slack_webhooks = {
      accountpage: "https://hooks.slack.com/services/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",
      growth_snackbar: "https://hooks.slack.com/services/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",
      growth_turkey: "https://hooks.slack.com/services/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",
      growth_holidayroast: "https://hooks.slack.com/services/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",
      growth_lambtopper: "https://hooks.slack.com/services/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",
      growth_treats: "https://hooks.slack.com/services/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",
      growth_kibble: "https://hooks.slack.com/services/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",
      growth: "https://hooks.slack.com/services/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"
    }
    config.emails = {
      temp_user: "temp-user@kabo.co",
      help: "help@kabo.co"
    }
    config.airtable = {
      api_key: "keydimZCpsszg7Vez",
      app_key: "appSjmgLxrzrIGcN6",
      subscription_cancel_app_key: "appiOFOflVtMygAtC",
      subscription_resume_app_key: "apposChn4Ra3STOgW"
    }
    config.facebook_access_token = ENV.fetch("FACEBOOK_ACCESS_TOKEN", "")
    config.recipe_images = {
      beef: "https://storage.googleapis.com/kabo-app/beef.png",
      chicken: "https://storage.googleapis.com/kabo-app/chicken.png",
      lamb: "https://storage.googleapis.com/kabo-app/lamb.png",
      turkey: "https://storage.googleapis.com/kabo-app/turkey.png",
      kibble: "https://storage.googleapis.com/kabo-app/kibble.png"
    }

    config.autoload_paths << Rails.root.join("lib")
  end
end
