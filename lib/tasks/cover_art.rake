# frozen_string_literal: true

# One-off maintenance for game cover art. After changing the master/variant
# dimensions (Game::CoverArt::Normalizer::MASTER_* and Game::COVER_VARIANT),
# run `cover_art:regenerate` to re-render every cover at the new size, then
# `cover_art:purge_orphans` to delete the old-size blobs left behind.
namespace :cover_art do
  desc "Re-render every game's cover at the current master/variant size (force)"
  task regenerate: :environment do
    scope = Game.where.not(cover_image_id: nil)
    total = scope.count
    ok = 0
    failed = []

    w = Game::CoverArt::Normalizer::MASTER_W
    h = Game::CoverArt::Normalizer::MASTER_H
    puts "Regenerating cover art for #{total} game(s) at #{w}×#{h}…"

    scope.find_each.with_index(1) do |game, i|
      Game::CoverArt::Normalizer.new(game: game, force: true).call
      ok += 1
      puts "[#{i}/#{total}] ##{game.id} #{game.title} — ok"
    rescue StandardError => e
      failed << game.id
      puts "[#{i}/#{total}] ##{game.id} #{game.title} — FAILED: #{e.class}: #{e.message}"
    end

    puts "Done: #{ok}/#{total} regenerated, #{failed.size} failed#{failed.empty? ? '' : " (ids: #{failed.join(', ')})"}."
    puts "Next: `rake cover_art:purge_orphans` to delete the old-size blobs."
  end

  desc "Purge ActiveStorage blobs no longer attached to any record (old cover sizes)"
  task purge_orphans: :environment do
    # Snapshot ids first — purging mutates the `unattached` scope, so iterating
    # it directly (find_each) skips rows as the set shrinks mid-batch.
    ids = ActiveStorage::Blob.unattached.pluck(:id)
    puts "Unattached blobs before: #{ids.size}"
    ids.each { |id| ActiveStorage::Blob.find_by(id:)&.purge }
    after = ActiveStorage::Blob.unattached.count
    puts "Purged #{ids.size - after} orphaned blob(s). Remaining unattached: #{after}."
  end
end
