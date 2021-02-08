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
        promo_banner = {
          text: "Surprise! We applied a 40% discount to your first order"
        }
        render json: { promo_banner: promo_banner }.merge(start_data), status: 200
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
        image: nil,
        description: "A lean protein diet with hearty grains. Made with Canadian-sourced chicken.",
        new: false,
        analysis: Constants::CHICKEN_ANALYSIS
      },
      {
        name: "Savoury Beef",
        recipe: "beef",
        image: nil,
        description: "A grain-free diet, perfect for picky eaters! Made from locally-sourced beef.",
        new: false,
        analysis: Constants::BEEF_ANALYSIS
      },
      {
        name: "Hearty Turkey",
        recipe: "turkey",
        image: nil,
        description: "Made with lean, locally-sourced turkey breast. Low-Fat. Gluten-Free.",
        new: false,
        analysis: Constants::TURKEY_ANALYSIS
      },
      {
        name: "Luscious Lamb",
        recipe: "lamb",
        image: nil,
        description: "Made with premium Ontario lamb. A novel protein choice for picky eaters and senior dogs!",
        new: true,
        analysis: Constants::LAMB_ANALYSIS
      }
    ]

    kibbles = [
      {
        name: "Chicken",
        recipe: "chicken",
        image: nil,
        description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
        new: false,
        analysis: Constants::CHICKEN_KIBBLE_ANALYSIS
      },
      {
        name: "Turkey & Salmon",
        recipe: "turkey+salmon",
        image: nil,
        description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
        new: false,
        analysis: Constants::TURKEY_SALMON_KIBBLE_ANALYSIS
      },
      {
        name: "Duck",
        recipe: "duck",
        image: nil,
        description: "Locally-sourced dry dog food, made with high quality ingredients you can trust.",
        new: false,
        analysis: Constants::DUCK_KIBBLE_ANALYSIS
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
      dog_ids = portions_params[:dog_ids].split(",")
      daily_portions = {}
      dog_ids.each do |dog_id|
        temp_dog = TempDog.find_by(id: dog_id)
        if temp_dog.present?
          daily_portions[dog_id] = temp_dog.daily_portions
        end
      end

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
  def create
    temp_user = TempUser.create({ temp_dogs_attributes: onboarding_params[:dogs] })

    render json: {
      status: true,
      temp_user_id: temp_user.id,
      temp_dog_ids: temp_user.temp_dog_ids
    }, status: 200
  end

  # Update
  def update
    temp_user = TempUser.find(params[:user_id])
    if temp_user.nil?
      render json: {
        status: false,
        err: "Temp User doesn't exist!"
      }, status: 500
    else
      step = onboarding_params[:step]
      if ["detail", "recipes"].include? step
        temp_user.update({ temp_dogs_attributes: onboarding_params[:dogs] })

        render json: {
          status: true,
          temp_user_id: temp_user.id,
          temp_dog_ids: temp_user.temp_dog_ids
        }, status: 200
      end
    end
  end

  private
    def dog_params
      params.permit(:step, :input)
    end

    def portions_params
      params.permit(:dog_ids)
    end

    def portions_params_valid?
      portions_params.present?
    end

    def onboarding_params
      case params[:step]
      when "start"
        params.require(:onboarding).permit(:step, dogs: [:name, :breed, :age_in_months]).to_h
      when "detail"
        params.require(:onboarding).permit(:step, dogs: [:id, :gender, :neutered, :weight, :weight_unit, :body_type, :activity_level])
      when "recipes"
        params.require(:onboarding).permit(:step, dogs: [:id, :chicken_recipe, :beef_recipe, :turkey_recipe, :lamb_recipe, :kibble_recipe])
      end
    end
end
