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
    end
  end
end
