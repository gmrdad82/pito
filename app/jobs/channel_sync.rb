class ChannelSync
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  # Phase B placeholder: flips the syncing flag on, performs a no-op (real
  # public + OAuth API work lands in a later phase), then flips it off and
  # records last_synced_at. The ensure block tolerates mid-flight deletion.
  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return unless channel

    channel.update!(syncing: true)

    # placeholder no-op — real YouTube sync lands later
  ensure
    if Channel.exists?(id: channel_id)
      Channel.find_by(id: channel_id)&.update(syncing: false, last_synced_at: Time.current)
    end
  end
end
