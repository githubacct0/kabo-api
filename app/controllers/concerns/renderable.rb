# frozen_string_literal: true

module Renderable
  extend ActiveSupport::Concern

  def render_missed_params
    render json: {
      error: "Missed params!"
    }, status: :bad_request
  end
end
