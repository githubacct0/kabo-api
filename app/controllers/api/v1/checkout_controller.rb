# frozen_string_literal: true

class Api::V1::CheckoutController < ApplicationController
  def estimate
    temp_user = TempUser.find_by(checkout_token: params[:checkout_token])
    if temp_user.present?
      temp_dog = TempDog.find_by(id: estimate_params[:temp_dog_id])
      if temp_dog.present?
        case params[:type]
        when "apply_referral_code"
          render json: {
            checkout_esimate: MyLib::Checkout.estimate_v2(temp_user, temp_dog, estimate_params[:referral_code], estimate_params[:referral_code], estimate_params[:postal_code])
          }, status: :ok
        when "recalculate"
          render json: {
            checkout_esimate: MyLib::Checkout.estimate_v2(temp_user, temp_dog, estimate_params[:referral_code], estimate_params[:referral_code], estimate_params[:postal_code])
          }, status: :ok
        end
      else
        render json: {
          error: "Temp dog does not exist"
        }, status: :not_found
      end
    else
      render json: {
        error: "Temp user does not exist"
      }, status: :not_found
    end
  end

  def validate_postal_code
    postal_code = params[:postal_code].strip
    render json: {
      valid: postal_code.length == 6 && MyLib::Checkout.serviceable_postal_code(postal_code)
    }, status: :ok
  end

  private
    def estimate_params
      case params[:type]
      when "apply_referral_code"
        params.require(:checkout).permit(:temp_dog_id, :postal_code, :referral_code)
      when "recalculate"
        params.require(:checkout).permit(:temp_dog_id, :postal_code, :referral_code)
      end
    end
end
