FactoryBot.define do
  factory :notification do
    kind { :calendar_entry_firing }
    event_type { "calendar_entry_firing" }
    severity { :info }
    title { "test notification" }
    body { nil }
    url { nil }
    event_payload { {} }
    fires_at { Time.current }
    retry_count { 0 }

    # Default trait — calendar-derived. Most tests want a typed-FK row
    # because that is the dominant shape (game_release / milestone_auto
    # / video_scheduled all flow through `source_calendar_entry`).
    transient do
      with_calendar_entry { true }
    end

    after(:build) do |notif, ev|
      if notif.source_calendar_entry_id.nil? && notif.dedup_key.nil? && ev.with_calendar_entry
        notif.source_calendar_entry = create(:calendar_entry)
      end
    end

    trait :with_calendar_entry do
      with_calendar_entry { true }
    end

    trait :with_dedup_key do
      with_calendar_entry { false }
      sequence(:dedup_key) { |n| "dedup-#{n}" }
    end

    trait :read do
      in_app_read_at { 1.minute.ago }
    end

    trait :unread do
      in_app_read_at { nil }
    end

    trait :discord_delivered do
      discord_delivered_at { 1.minute.ago }
    end

    trait :slack_delivered do
      slack_delivered_at { 1.minute.ago }
    end

    trait :video_published do
      kind { :video_published }
      event_type { "video_published" }
      severity { :info }
      title { "video published" }
    end

    trait :video_pre_publish_check_missed do
      kind { :video_pre_publish_check_missed }
      event_type { "video_pre_publish_check_missed" }
      severity { :info }
      title { "pre-publish check skipped" }
      with_calendar_entry { false }
      sequence(:dedup_key) { |n| "missed-check-#{n}" }
    end

    trait :game_release_upcoming do
      kind { :game_release_upcoming }
      event_type { "game_release_upcoming" }
      severity { :info }
      title { "upcoming release" }
    end

    trait :game_release_today do
      kind { :game_release_today }
      event_type { "game_release_today" }
      severity { :success }
      title { "released today" }
    end

    trait :milestone_reached do
      kind { :milestone_reached }
      event_type { "milestone_reached" }
      severity { :success }
      title { "milestone reached" }
    end

    trait :calendar_entry_firing do
      kind { :calendar_entry_firing }
      event_type { "calendar_entry_firing" }
      severity { :info }
      title { "calendar entry firing" }
    end

    trait :sync_error do
      kind { :sync_error }
      event_type { "sync_error" }
      severity { :urgent }
      title { "sync error" }
      with_calendar_entry { false }
      sequence(:dedup_key) { |n| "sync-error-#{n}" }
    end

    trait :youtube_reauth_needed do
      kind { :youtube_reauth_needed }
      event_type { "youtube_reauth_needed" }
      severity { :urgent }
      title { "youtube re-auth needed" }
      with_calendar_entry { false }
      sequence(:dedup_key) { |n| "youtube-reauth-#{n}" }
    end
  end
end
