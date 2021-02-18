# frozen_string_literal: true

module Renderable
  extend ActiveSupport::Concern

  def render_missed_params
    render json: {
      error: "Missed params!"
    }, status: :bad_request
  end

  def render_error(error, status)
    render json: {
      error: error
    }, status: status
  end
end
