FactoryBot.define do
  factory :bulk_operation do
    kind { :update_metadata }
    status { :pending }
    parameters { { title_prefix: "New" } }
    target_video_ids { [] }
  end
end
