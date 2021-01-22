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

    config.mailgun_api_key = ENV.fetch("MAILGUN_API_KEY")
    config.heroku = {
      app_id: ENV.fetch("HEROKU_APP_ID"),
      app_name: ENV.fetch("HEROKU_APP_NAME"),
      release_created_at: ENV.fetch("HEROKU_RELEASE_CREATED_AT"),
      release_version: ENV.fetch("HEROKU_RELEASE_VERSION"),
      slug_commit: ENV.fetch("HEROKU_SLUG_COMMIT"),
      slug_description: ENV.fetch("HEROKU_SLUG_DESCRIPTION")
    }

    config.autoload_paths << Rails.root.join("lib")
  end
end
