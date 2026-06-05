class SyncStarredChannelsJob < ApplicationJob
  queue_as :default

  # Cron-triggered. Enqueues a ChannelSync job per starred channel.
  def perform
    Channel.where(star: true).find_each do |channel|
      ChannelSync.perform_later(channel.id)
    end
  end
end
