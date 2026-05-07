FactoryBot.define do
  factory :bulk_operation do
    tenant { Current.tenant || association(:tenant) }
    kind { :update_metadata }
    status { :pending }
    parameters { { title_prefix: "New" } }
    target_video_ids { [] }
  end
end
