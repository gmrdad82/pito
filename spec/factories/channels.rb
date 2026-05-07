FactoryBot.define do
  factory :channel do
    # Phase 5A — reuse Current.tenant if the example already pinned
    # one (the default for non-request specs via support/tenant_context).
    # That way factory-created channels live in the same tenant
    # default-scope queries see, and existing specs keep passing
    # without explicit tenant plumbing.
    tenant { Current.tenant || association(:tenant) }

    # Deterministic 22-char base62 suffix per sequence index, padded with
    # alphanumerics. Stays inside the regex `\A[A-Za-z0-9_-]{22}\z`.
    sequence(:channel_url) do |n|
      base = n.to_s
      filler_chars = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a
      pad_length = 22 - base.length
      pad = pad_length.positive? ? Array.new(pad_length) { |i| filler_chars[(n * 7 + i) % filler_chars.length] }.join : ""
      "https://www.youtube.com/channel/UC#{(base + pad)[0, 22]}"
    end

    star { false }
    connected { false }
    syncing { false }
    last_synced_at { nil }

    trait :starred do
      star { true }
    end

    trait :connected do
      connected { true }
    end

    trait :syncing do
      syncing { true }
    end

    trait :fully_loaded do
      star { true }
      connected { true }
      syncing { true }
      last_synced_at { Time.current }
    end
  end
end
