FactoryBot.define do
  factory :calendar_entry do
    title { "calendar entry" }
    starts_at { 1.day.from_now }
    all_day { false }
    timezone { "UTC" }
    source { :manual }
    state { :scheduled }
    entry_type { :custom }
    metadata { {} }

    # Default trait — `custom` (free-form, no FKs). Tests pick a specific
    # trait to exercise typed-FK paths.
    trait :channel_published do
      entry_type { :channel_published }
      source { :derived }
      state { :occurred }
      all_day { true }
      title { "channel joined: example" }
      transient do
        channel_record { create(:channel) }
      end
      channel { channel_record }
      source_ref { { channel_id: channel_record.id } }
    end

    trait :video_published do
      entry_type { :video_published }
      source { :derived }
      state { :occurred }
      title { "video published: example" }
      starts_at { 1.day.ago }
      transient do
        video_record { create(:video) }
      end
      video { video_record }
      source_ref { { video_id: video_record.id, kind: "published" } }
    end

    trait :video_scheduled do
      entry_type { :video_scheduled }
      source { :derived }
      state { :scheduled }
      title { "scheduled: example" }
      starts_at { 2.days.from_now }
      transient do
        video_record { create(:video) }
      end
      video { video_record }
      source_ref { { video_id: video_record.id, kind: "scheduled" } }
    end

    trait :game_release do
      entry_type { :game_release }
      source { :manual }
      state { :scheduled }
      all_day { true }
      title { "released: example" }
      starts_at { 30.days.from_now }
      release_precision { :day }
      game { association(:game, strategy: :create) }
    end

    trait :purchase_planned do
      entry_type { :purchase_planned }
      source { :manual }
      state { :scheduled }
      title { "preorder: example @ Steam" }
      transient do
        parent { create(:calendar_entry, :game_release) }
      end
      parent_entry { parent }
      metadata do
        {
          "purchase_kind" => "preorder",
          "storefront" => "Steam",
          "amount" => "39.99",
          "currency" => "EUR"
        }
      end
    end

    trait :milestone_manual do
      entry_type { :milestone_manual }
      source { :manual }
      state { :scheduled }
      title { "podcast appearance" }
      starts_at { 7.days.from_now }
    end

    trait :milestone_auto do
      entry_type { :milestone_auto }
      source { :auto }
      state { :occurred }
      title { "100k subs" }
      starts_at { 1.hour.ago }
      transient do
        rule { create(:milestone_rule) }
      end
      milestone_rule { rule }
      source_ref do
        { milestone_rule_id: rule.id, metric_value_at_fire: 100_000 }
      end
      metadata do
        { "metric_value_at_fire" => 100_000, "user_overrides" => {} }
      end
    end

    trait :custom do
      entry_type { :custom }
      source { :manual }
      state { :scheduled }
      title { "ad-hoc note" }
      metadata { { "tags" => %w[ops note] } }
    end

    trait :occurred do
      state { :occurred }
    end

    trait :cancelled do
      state { :cancelled }
    end

    trait :superseded do
      state { :superseded }
    end

    trait :all_day do
      all_day { true }
    end
  end
end
