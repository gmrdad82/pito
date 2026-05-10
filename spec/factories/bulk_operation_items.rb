FactoryBot.define do
  factory :bulk_operation_item do
    bulk_operation

    video do
      channel = association(:channel)
      association(:video, channel: channel)
    end

    target { video }
    status { :pending }
  end
end
