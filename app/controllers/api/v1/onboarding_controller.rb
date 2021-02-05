# frozen_string_literal: true

class Api::V1::OnboardingController < ActionController::API
  def index
    step = dog_params[:step]

    if step == "start"
      breeds = Breed.find_each.reject { |breed| breed.name&.downcase == "unknown" }.map { |breed|
        { label: breed.name, value: breed.id }
      }

      ages = Constants::AGE_OPTIONS.map { |age|
        { label: age[0], value: age[1] }
      }

      render json: {
        breeds: breeds,
        ages: ages
      }, status: 200
    elsif step == "detail"
      genders = ["Female", "Male"].map { |gender|
        { label: gender, value: gender == "Male" }
      }

      weight_units = [ 0, "lbs", "kg" ].map { |unit|
        { label: unit, value: unit }
      }

      body_types = %w(
        Skinny
        Ideal
        Rounded
        Chunky
      ).each_with_index.map { |type, index|
        { label: type, value: index }
      }

      activity_levels = %w(
        Lazy
        Ideal
        Very\ active
      ).each_with_index.map { |type, index|
        { label: type, value: index }
      }

      render json: {
        genders: genders,
        weight_units: weight_units,
        body_types: body_types,
        activity_levels: activity_levels
      }
    end
  end

  private
    def dog_params
      params.permit(:step)
    end
end
