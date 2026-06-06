# frozen_string_literal: true

namespace :pito do
  namespace :voyage do
    desc "Backfill channel embeddings (one ChannelVoyageIndexJob per channel)"
    task reindex_channels: :environment do
      count = 0
      Channel.find_each do |channel|
        ChannelVoyageIndexJob.perform_later(channel.id)
        count += 1
      end
      puts "Enqueued #{count} ChannelVoyageIndexJob(s)."
    end
  end
end
