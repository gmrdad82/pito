# frozen_string_literal: true

namespace :pito do
  namespace :voyage do
    desc "Backfill video embeddings (one VideoVoyageIndexJob per video)"
    task reindex_videos: :environment do
      count = 0
      Video.find_each do |video|
        VideoVoyageIndexJob.perform_later(video.id)
        count += 1
      end
      puts "Enqueued #{count} VideoVoyageIndexJob(s)."
    end

    desc "Backfill game embeddings (one GameVoyageIndexJob per game)"
    task reindex_games: :environment do
      count = 0
      Game.find_each do |game|
        GameVoyageIndexJob.perform_later(game.id)
        count += 1
      end
      puts "Enqueued #{count} GameVoyageIndexJob(s)."
    end
  end
end
