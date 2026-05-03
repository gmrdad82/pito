FactoryBot.define do
  factory :user do
    tenant
    sequence(:username) { |n| "user#{n}" }
    sequence(:email)    { |n| "user#{n}@example.test" }
    password { "password123" }
    password_confirmation { "password123" }
  end
end
