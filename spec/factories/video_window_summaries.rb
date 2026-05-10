FactoryBot.define do
  factory :video_window_summary do
    video
    window         { "28d" }
    window_start   { 28.days.ago.to_date }
    window_end     { Date.current }

    trait :seven_d do
      window       { "7d" }
      window_start { 7.days.ago.to_date }
      window_end   { Date.current }
    end

    trait :twenty_eight_d do
      window       { "28d" }
      window_start { 28.days.ago.to_date }
      window_end   { Date.current }
    end

    trait :ninety_d do
      window       { "90d" }
      window_start { 90.days.ago.to_date }
      window_end   { Date.current }
    end

    trait :lifetime do
      window       { "lifetime" }
      window_start { 5.years.ago.to_date }
      window_end   { Date.current }
    end
  end
end
