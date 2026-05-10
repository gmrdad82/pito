FactoryBot.define do
  factory :top_videos_window do
    # The factory builds an isolated channel + video pair so the
    # leaderboard row's video is hosted by the channel by default.
    transient do
      host_channel { nil }
    end

    channel { host_channel || association(:channel) }
    video   { association(:video, channel: channel) }

    window { "28d" }
    sequence(:rank) { |n| n }

    trait :seven_d        do; window { "7d" };       end
    trait :twenty_eight_d do; window { "28d" };      end
    trait :ninety_d       do; window { "90d" };      end
    trait :lifetime       do; window { "lifetime" }; end
  end
end
