# frozen_string_literal: true

module MyLib
  class Home
    class << self
      def plan_units(interval, meal_type, calories)
        meal_percentage = meal_type.split("_")[0].to_i/100.0
        calories_for_meal_per_day = meal_percentage*calories

        ounces_for_meal_per_day = (calories_for_meal_per_day/43)

        ounces_for_meal_during_plan_interval = ounces_for_meal_per_day*14 # for 2 weeks

        if interval  == "4_weeks"
          ounces_for_meal_during_plan_interval = ounces_for_meal_during_plan_interval*2
        end

        ounces_for_meal_during_plan_interval.floor
      end
    end
  end
end
