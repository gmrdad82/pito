FactoryBot.define do
  factory :import_job do
    channel
    association :enqueued_by, factory: :user
    status { :queued }
    total_videos { 0 }
    imported_videos { 0 }
    failed_videos { 0 }

    trait :running do
      status { :running }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      total_videos { 5 }
      imported_videos { 5 }
    end

    trait :failed do
      status { :failed }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      error_payload { { "code" => "no_uploads_playlist", "message" => "missing uploads playlist" } }
    end
  end
end
