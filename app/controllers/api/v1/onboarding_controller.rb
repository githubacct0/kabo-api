# frozen_string_literal: true

class Api::V1::OnboardingController < ActionController::API
  include Renderable

  # Route: /api/v1/onboarding/signup
  # Method: GET
  # Get dog options
  def index
    input = dog_params[:input]

    breeds = Dog.breeds
    unknown_breeds = Dog.unknown_breeds
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

      render json: data, status: :ok
    else
      step = dog_params[:step]

      start_data = {
        breeds: breeds,
        unknown_breeds: unknown_breeds,
        ages: ages
      }

      detail_data = {
        genders: genders,
        weight_units: weight_units,
        body_types: body_types,
        activity_levels: activity_levels
      }

      if step.nil?
        render json: start_data.merge(detail_data), status: :ok
      elsif step == "start"
        promo_banner = {
          text: "Surprise! We applied a 40% discount to your first order"
        }
        render json: { promo_banner: promo_banner }.merge(start_data), status: :ok
      elsif step == "detail"
        render json: detail_data, status: :ok
      else
        render json: {}, status: :bad_request
      end
    end
  end

  # Route: /api/v1/onboarding/recipes
  # Method: GET
  # Get recipes
  def recipes
    render json: {
      cooked_recipes: Dog.cooked_recipes,
      kibble_recipes: Dog.kibble_recipes
    }, status: :ok
  end

  # Route: /api/v1/onboarding/portions
  # Method: GET
  # Get daily portions
  def portions
    if portions_params_valid?
      dog_ids = portions_params[:dog_ids].split(",")
      daily_portions = {}
      dog_ids.each do |dog_id|
        temp_dog = TempDog.find_by(id: dog_id)
        daily_portions[dog_id] = temp_dog.present? ? temp_dog.daily_portions(type: "onboarding") : []
      end

      render json: {
        daily_portions: daily_portions
      }, status: :ok
    else
      render_missed_params
    end
  end

  # Route: /api/v1/onboarding/users
  # Method: POST
  # Create temp user
  def create
    if onboarding_params_valid?
      begin
        temp_user = TempUser.create!
        temp_user.temp_dogs.create!(onboarding_params[:dogs])

        render json: {
          temp_user_id: temp_user.id,
          temp_dog_ids: temp_user.temp_dog_ids
        }, status: :ok
      rescue => e
        puts "Error: #{e.message}"

        render json: {
          error: e.message
        }, status: :bad_request
      end
    else
      render_missed_params
    end
  end

  # Route: /api/v1/onboarding/users/:user_id
  # Method: PUT
  # Update user and dogs
  def update
    if onboarding_params_valid?
      temp_user = TempUser.find_by_id(params[:user_id])
      if temp_user.nil?
        render json: {
          error: "Temp User doesn't exist!"
        }, status: :not_found
      else
        step = onboarding_params[:step]
        update_params = {}

        if ["detail", "recipes", "portions"].include?(step)
          update_params[:plan_interval] = onboarding_params[:plan_interval] if step == "portions"
          update_params[:temp_dogs_attributes] = onboarding_params[:dogs]
          begin
            temp_user.update!(update_params)

            render json: {
              temp_user_id: temp_user.id,
              temp_dog_ids: temp_user.temp_dog_ids
            }, status: :ok
          rescue => e
            puts "app_log(ERROR): #{e.message}"
            render_error("", :not_found, true)
          end
        elsif step == "account"
          onboarding_params[:first_name].present? && update_params[:first_name] = onboarding_params[:first_name]
          onboarding_params[:email].present? && update_params[:email] = onboarding_params[:email]
          email = update_params[:email]
          if email.present?
            email_valid = TempUser.is_email_valid?(email)
          else
            email_valid = true
            update_params[:email] = "#{SecureRandom.uuid}-temp-user@kabo.co"
          end

          if email_valid
            checkout_token = SecureRandom.uuid
            update_params[:checkout_token] = checkout_token
            update_params[:chargebee_plan_interval] = "#{temp_user.calculated_trial_length}_weeks"
            temp_user.update(update_params)

            referral_code = onboarding_params[:referral_code]
            referral_check = MyLib::Referral.check_code(referral_code)
            applied_referral_code = referral_check ? "'#{referral_code}' used. #{referral_check} discount applied!" : "'40off' used. 40% discount applied!"

            # TAG: CHECK IF NEED
            if onboarding_params[:token].present?
              agreement_response = MyLib::Paypal.create_billing_agreement

              if Rack::Utils.parse_nested_query(agreement_response.body)["ACK"] == "Failure"
                render json: {
                  error: "Cancelled PayPal Authorization"
                }, status: :bad_request
              else
                details_response = MyLib::Paypal.get_express_checkout_details
                paypal_checkout_details = Rack::Utils.parse_nested_query(details_response.body)
                user = {
                  email: paypal_checkout_details["EMAIL"],
                  paypal_email: paypal_checkout_details["EMAIL"],
                  first_name: paypal_checkout_details["FIRSTNAME"],
                  shipping_last_name:  paypal_checkout_details["LASTNAME"],
                  shipping_street_address: paypal_checkout_details["SHIPTOSTREET"],
                  shipping_city: paypal_checkout_details["SHIPTOCITY"],
                  shipping_postal_code: paypal_checkout_details["SHIPTOZIP"].delete(" "),
                  reference_id: Rack::Utils.parse_nested_query(agreement_response.body)["BILLINGAGREEMENTID"]
                }

                temp_dogs = temp_user.dogs.map do |temp_dog|
                  {
                    id: temp_dog.id,
                    mean_plan: temp_dog.mean_plan,
                    topper_available: temp_dog.topper_available,
                    checkout_esimate: MyLib::Checkout.estimate_v2(temp_user, temp_dog, referral_code, referral_code, nil)
                  }
                end

                render json: {
                  temp_user_id: temp_user.id,
                  temp_dogs: temp_dogs,
                  user: user,
                  applied_referral_code: applied_referral_code,
                  paypal_checkout: true,
                  checkout_token: checkout_token,
                }, status: :ok
              end
            else
              temp_dogs = temp_user.temp_dogs.map { |temp_dog|
                {
                  name: temp_dog.name,
                  meal_type: temp_dog.meal_type,
                  checkout_estimate: MyLib::Checkout.estimate_v2(temp_user, temp_dog, referral_code, nil, nil, true)
                }
              }

              render json: {
                temp_user_id: temp_user.id,
                applied_referral_code: applied_referral_code,
                temp_dogs: temp_dogs
              }, status: :ok
            end
          else
            render json: {
              error: "Email is invalid!"
            }, status: :bad_request
          end
        end
      end
    else
      render_missed_params
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
      portions_params[:dog_ids].present?
    end

    def onboarding_params
      case params[:step]
      when "start"
        params.require(:onboarding).permit(:step, dogs: [:name, :breed, :age_in_months]).to_h
      when "detail"
        params.require(:onboarding).permit(:step, dogs: [:id, :gender, :neutered, :weight, :weight_unit, :body_type, :activity_level])
      when "recipes"
        params.require(:onboarding).permit(:step, dogs: [:id, :chicken_recipe, :beef_recipe, :turkey_recipe, :lamb_recipe, :kibble_recipe])
      when "portions"
        params.require(:onboarding).permit(:step, :plan_interval, dogs: [:id, :cooked_portion, :kibble_portion])
      when "account"
        params.require(:onboarding).permit(:step, :first_name, :email, :referral_code, :token)
      end
    end

    def onboarding_params_valid?
      step = params[:step]
      return false if step.nil?

      if ["start", "detail", "recipes"].include? step
        keys =
          case step
          when "start" then [:name, :breed, :age_in_months]
          when "detail" then [:id, :gender, :neutered, :weight, :weight_unit, :body_type, :activity_level]
          when "recipes" then [:id, :chicken_recipe, :beef_recipe, :turkey_recipe, :lamb_recipe, :kibble_recipe]
          end

        onboarding_params[:dogs].present? &&
          onboarding_params[:dogs].all? { |dog| keys.all? { |key| dog.key? key } }
      elsif step == "portions"
        keys = ["cooked_portion", "kibble_portion"]
        onboarding_params[:plan_interval].present? &&
          onboarding_params[:dogs].present? &&
          onboarding_params[:dogs].all? { |dog|
            dog.key?("id") && (keys & dog.keys).any?
          }
      elsif step == "account"
        onboarding_params[:first_name].present? &&
          onboarding_params[:email].present?
      else
        false
      end
    end
end
