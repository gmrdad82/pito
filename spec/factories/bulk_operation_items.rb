FactoryBot.define do
  factory :bulk_operation_item do
    bulk_operation
    video
    status { :pending }
  end
end
