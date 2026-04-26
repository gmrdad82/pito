FactoryBot.define do
  factory :app_setting do
    sequence(:key) { |n| "setting_#{n}" }
    value { Faker::Lorem.word }
  end
end
