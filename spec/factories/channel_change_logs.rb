FactoryBot.define do
  factory :channel_change_log do
    channel
    association :changed_by_user, factory: :user
    field { "title" }
    old_value { "old" }
    new_value { "new" }
    changed_at { Time.current }
  end
end
