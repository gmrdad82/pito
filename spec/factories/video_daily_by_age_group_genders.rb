FactoryBot.define do
  factory :video_daily_by_age_group_gender do
    video
    sequence(:date)      { |n| Date.current - (n + 1).days }
    sequence(:age_group) { |n| %w[AGE_13_17 AGE_18_24 AGE_25_34 AGE_35_44 AGE_45_54 AGE_55_64 AGE_65_PLUS][n % 7] }
    sequence(:gender)    { |n| %w[FEMALE MALE GENDER_OTHER][n % 3] }
  end
end
