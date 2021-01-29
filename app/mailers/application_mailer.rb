# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "Kabo <#{Rails.configuration.emails[:help]}>"
  layout "mailer"
end
