FactoryBot.define do
  factory :rejected_video_import do
    channel
    association :rejected_by, factory: :user
    # 11-char YouTube-id-shaped string, deterministic per sequence.
    sequence(:youtube_video_id) do |n|
      chars = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[_ -]
      Array.new(11) { |i| chars[(n * 7 + i * 3) % chars.size] }.join
    end
    rejected_at { Time.current }
  end
end
