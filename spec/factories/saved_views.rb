FactoryBot.define do
  factory :saved_view do
    tenant { Current.tenant || association(:tenant) }
    kind { :channels }
    sequence(:url) { |n| "/channels?view=#{n}" }
    sequence(:name) { |n| "View #{n}" }
    position { 0 }

    trait :videos do
      kind { :videos }
      sequence(:url) { |n| "/videos?view=#{n}" }
    end
  end
end
