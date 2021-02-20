# frozen_string_literal: true

module Renderable
  extend ActiveSupport::Concern

  def render_missed_params
    render json: {
      error: "Missed params!"
    }, status: :bad_request
  end

  def render_error(error, status, contactable = false)
    contact = {
      message: "please contact help@kabo.co if you're experiencing any issues"
    }
    error = error.to_s + " " + contact[:message] if contactable

    render json: {
      error: error
    }, status: status
  end

  def render_contact_error(status)
    render json: {
      error: "Please contact help@kabo.co if you're experiencing any issues"
    }, status: status
  end
end
