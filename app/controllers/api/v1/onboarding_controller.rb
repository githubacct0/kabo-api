# frozen_string_literal: true

class Api::V1::OnboardingController < ActionController::API
  def index
    input = dog_params[:input]

    breeds = Dog.breeds
    ages = Dog.ages
    genders = Dog.genders
    weight_units = Dog.weight_units
    body_types = Dog.body_types
    activity_levels = Dog.activity_levels

    if input.present?
      input_params = input.split(",")
      data = {}
      input_params.include?("breeds") && data.merge!({ breeds: breeds })
      input_params.include?("ages") && data.merge!({ ages: ages })
      input_params.include?("genders") && data.merge!({ genders: genders })
      input_params.include?("weight_units") && data.merge!({ weight_units: weight_units })
      input_params.include?("body_types") && data.merge!({ body_types: body_types })
      input_params.include?("activity_levels") && data.merge!({ activity_levels: activity_levels })

      render json: data, status: 200
    else
      step = dog_params[:step]

      start_data = {
        breeds: breeds,
        ages: ages
      }

      detail_data = {
        genders: genders,
        weight_units: weight_units,
        body_types: body_types,
        activity_levels: activity_levels
      }

      if step == "start"
        render json: start_data, status: 200
      elsif step == "detail"
        render json: detail_data, status: 200
      else
        render json: start_data.merge(detail_data), status: 200
      end
    end
  end

  # Get recipes
  def recipes
    recipes = [
      {
        name: "Tender Chicken",
        recipe: "chicken",
        image: ""
      },
      {
        name: "Savoury Beef",
        recipe: "beef",
        image: ""
      },
      {
        name: "Hearty Turkey",
        recipe: "turkey",
        image: ""
      },
      {
        name: "Luscious Lamb",
        recipe: "lamb",
        image: ""
      }
    ]

    kibbles = [
      {
        name: "Chicken",
        recipe: "chicken",
        image: ""
      },
      {
        name: "Turkey & Salmon",
        recipe: "turkey+salmon",
        image: ""
      },
      {
        name: "Duck",
        recipe: "duck",
        image: ""
      }
    ]

    render json: {
      recipes: recipes,
      kibbles: kibbles
    }, status: 200
  end

  # Get daily portions
  def portions
    if portions_params_valid?
      dog = portions_params[:dog]
      daily_portions = [
        {
          portion: 25,
          description: "About 25% of #{dog}’s daily caloric needs. Mix it in with their current food to give them the nutrients of fresh food at a more affordable price point!"
        },
        {
          portion: 100,
          description: "A complete and balanced diet for #{dog}. You will receive enough food for 100% of #{dog}’s daily caloric needs, which is 1091 calories."
        }
      ]
      render json: {
        daily_portions: daily_portions
      }, status: 200
    else
      render json: {
        status: false,
        err: "Missed params!"
      }, status: 500
    end
  end

  # Create temp user
  def create_temp_user
    temp_user = TempUser.new
    temp_user.save(validate: false)

    render json: {
      temp_user_id: temp_user.id
    }, status: 200
  end

  private
    def dog_params
      params.permit(:step, :input)
    end

    def portions_params
      params.permit(:dog)
    end

    def portions_params_valid?
      portions_params.present?
    end
end
