class SyncStarredChannelsJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  # Cron-triggered (see config/sidekiq_cron.yml). Enqueues a ChannelSync job
  # per starred channel.
  def perform
    Channel.where(star: true).find_each do |channel|
      ChannelSync.perform_async(channel.id)
    end
  end
end
