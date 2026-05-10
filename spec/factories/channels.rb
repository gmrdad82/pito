FactoryBot.define do
  factory :channel do
    # Deterministic 22-char base62 suffix per sequence index, padded with
    # alphanumerics. Stays inside the regex `\A[A-Za-z0-9_-]{22}\z`.
    sequence(:channel_url) do |n|
      base = n.to_s
      filler_chars = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a
      pad_length = 22 - base.length
      pad = pad_length.positive? ? Array.new(pad_length) { |i| filler_chars[(n * 7 + i) % filler_chars.length] }.join : ""
      "https://www.youtube.com/channel/UC#{(base + pad)[0, 22]}"
    end

    # Channel is a thin YouTube-reference record: channel_url, star,
    # youtube_connection_id, last_synced_at. The legacy `connected`
    # boolean was retired alongside its derived semantic surface; tests
    # that need an OAuth-linked channel pass an explicit
    # `youtube_connection:` association instead of relying on a trait.
    star { false }
    last_synced_at { nil }

    trait :starred do
      star { true }
    end
  end
end
