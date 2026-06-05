# Pito game-score tasks.
namespace :pito do
  namespace :tools do
    namespace :games do
      desc "Backfill the computed `score` for every game that has IGDB rating data."
      task backfill_scores: :environment do
        total = Game.count
        updated = 0
        skipped = 0

        Game.find_each do |game|
          before = game.score
          game.recompute_score!
          after = game.reload.score

          if before != after
            updated += 1
            puts "  #{game.id} #{game.title[0..60]}: #{before.inspect} → #{after}"
          else
            skipped += 1
          end
        end

        puts ""
        puts "Done. #{updated} updated, #{skipped} unchanged (out of #{total})."
      end

      desc "Re-sync release-date components for every game with an igdb_id."
      task resync_release_dates: :environment do
        scope = Game.where.not(igdb_id: nil)
        total = scope.count
        enqueued = 0

        scope.find_each do |game|
          GameIgdbSync.perform_later(game.id)
          enqueued += 1
          puts "  Enqueued #{game.id} #{game.title[0..60]}"
        end

        puts ""
        puts "Done. #{enqueued} jobs enqueued (out of #{total} games with igdb_id)."
      end
    end
  end
end
