# frozen_string_literal: true

class DeviseMailer < Devise::Mailer
  helper :application # gives access to all helpers defined within `application_helper`.
  include Devise::Controllers::UrlHelpers # Optional. eg. `confirmation_url`
  default template_path: "devise/mailer", from: "Kabo <help@kabo.co>" # to make sure that your mailer uses the devise views
end
