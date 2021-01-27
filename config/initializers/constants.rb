module Constants
  CHARGEBEE_PLAN_INTERVAL_OPTIONS = [
    "2_weeks",
    "2_weeks_4_week-delay",
    "2_weeks_6_week-delay",
    "2_weeks_8_week-delay",
    "2_weeks_12_week-delay",
    "2_weeks_26_week-delay",
    "4_weeks",
    "4_weeks_6_week-delay",
    "4_weeks_8_week-delay",
    "4_weeks_12_week-delay",
    "4_weeks_26_week-delay"
  ]

  FEMALE = 'female'
  MALE = 'male'
  NO = 'no'
  YES = 'yes'
  LBS = 'lbs'
  KG = 'kg'

  MEAL_TYPES = ['food_restriction', '25_beef', '100_beef', '25_chicken', '100_chicken', '25_beef+chicken', '100_beef+chicken']

  AGE_OPTIONS = [
    ['less than 1 month', 0], ['1-4 months', 1], ['4-12 months', 4], ['1', 12], ['2', 24], ['3', 36], ['4', 48], ['5', 60],
    ['6', 72], ['7', 84], ['8', 96], ['9', 108], ['10', 120], ['11', 132], ['12', 144], ['13', 156], ['14', 168], ['15', 180], ['16', 192], ['17', 204],
    ['18', 216], ['19', 228], ['20', 240]
  ]

  LAMB_RECIPE = "Premium ground lamb, chickpeas, russet potato, squash, green beans, kale, broccoli, chia seeds, sunflower oil, fish oil, nutrient mix."
  BEEF_RECIPE = "Fresh ground beef, Russet potato, Sweet potato, Green beans, Carrots, Green peas, Red apples, Beef liver, Fish Oil, Nutrient Mix"
  CHICKEN_RECIPE = "Fresh ground chicken breast, Rice, Carrots, Green peas, Red apples, Chicken liver, Fish oil, Nutrient Mix"
  TURKEY_RECIPE = "Ground Turkey, Rice, Whole Egg, Carrots, Apples, Peas, Beans, Fish Oil, Nutrient Mix"
  CHICKEN_KIBBLE_RECIPE = "Chicken, Cranberries, Ginger, Pumpkin, Kelp, Kale"
  TURKEY_SALMON_KIBBLE_RECIPE = "Turkey, Salmon, Chickpeas, Faba beans"
  DUCK_KIBBLE_RECIPE = "Duck, Green peas, Lentils, Flax seed"

  BEEF_ANALYSIS = [
    ["Protein", "8% min"],
    ["Fat", "6% min"],
    ["Fiber", "1% max"],
    ["Moisture", "76% max"],
    ["Calorie Content", "1283 kcal/kg"]
  ]

  CHICKEN_ANALYSIS = [
    ["Protein", "11% min"],
    ["Fat", "1% min"],
    ["Fiber", "0.5% max"],
    ["Moisture", "77% max"],
    ["Calorie Content", "1077 kcal/kg"]
  ]

  TURKEY_ANALYSIS = [
    ["Protein", "16% min"],
    ["Fat", "6% min"],
    ["Fiber", "1% max"],
    ["Moisture", "68% max"],
    ["Calorie Content", "1493 kcal/kg"]
  ]

  LAMB_ANALYSIS = [
    ["Protein", "15% min"],
    ["Fat", "12% min"],
    ["Fiber", "1% max"],
    ["Moisture", "64% max"],
    ["Calorie Content", "1850 kcal/kg"]
  ]

  CHICKEN_KIBBLE_ANALYSIS = [
    ["Protein", "26% min"],
    ["Fat", "10% min"],
    ["Fiber", "5.0% max"],
    ["Moisture", "10.0% max"],
    ["Calorie Content", "3300 kcal/kg"]
  ]

  TURKEY_SALMON_KIBBLE_ANALYSIS = [
    ["Protein", "24% min"],
    ["Fat", "12% min"],
    ["Fiber", "4.0% max"],
    ["Moisture", "10.0% max"],
    ["Calorie Content", "3440 kcal/kg"]
  ]

  DUCK_KIBBLE_ANALYSIS = [
    ["Protein", "28% min"],
    ["Fat", "15% min"],
    ["Fiber", "4.0% max"],
    ["Moisture", "10.0% max"],
    ["Calorie Content", "3570 kcal/kg"]
  ]
end
