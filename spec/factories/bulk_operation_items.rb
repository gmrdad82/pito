FactoryBot.define do
  factory :bulk_operation_item do
    bulk_operation
    tenant { bulk_operation.tenant }

    # Build a video that shares the bulk_operation's tenant. Using the
    # block form so the Video factory's `tenant { channel.tenant }`
    # receives a channel already pinned to the right tenant.
    video do
      channel = association(:channel, tenant: bulk_operation.tenant)
      association(:video, channel: channel)
    end

    target { video }
    status { :pending }
  end
end
