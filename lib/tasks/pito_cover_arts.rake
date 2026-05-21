# Phase 27 follow-up (2026-05-17) — Cover-art master regen tasks.
#
# Two tasks for regenerating the normalized cover masters produced by
# `Game::CoverArt::Normalizer`:
#
#   bin/rails pito:cover_arts:regenerate
#     Regenerates every Game with a `cover_image_id`. The per-game
#     `<PITO_ASSETS_PATH>/covers/games/<game_id>/` directory is purged
#     before each normalize call so the Normalizer's mtime-based
#     idempotency check cannot short-circuit (a regen always re-fetches
#     IGDB bytes).
#
#   bin/rails pito:cover_arts:regenerate:game[ID]
#     Same operation scoped to a single Game by id. For ad-hoc fixes
#     when a specific master is wrong or missing. Only the targeted
#     game's directory is purged — masters for other games are left
#     untouched.
#
# Neither task is wired into deploy automation. Hetzner deploys run
# the bulk regen task manually when the canonical normalization rules
# (dimensions, JPEG quality, source token) change.
require "fileutils"

namespace :pito do
  namespace :cover_arts do
    desc "Regenerate normalized cover masters for every Game with a cover_image_id"
    task regenerate: :environment do
      games = Game.where.not(cover_image_id: [ nil, "" ]).order(:title)
      total = games.count
      successes = 0
      failures = []

      puts "[pito:cover_arts:regenerate] processing #{total} game#{'s' if total != 1}..."

      games.each_with_index do |game, idx|
        index_str = format("%3d/%-3d", idx + 1, total)
        target_dir = Pito::AssetsRoot.path("covers", "games", game.id.to_s)
        FileUtils.rm_rf(target_dir) if File.directory?(target_dir)

        begin
          path = Game::CoverArt::Normalizer.new(game: game).call
          if path
            successes += 1
            puts "[#{index_str}] OK   #{game.title.inspect} → #{path}"
          else
            puts "[#{index_str}] SKIP #{game.title.inspect} (no cover_image_id)"
          end
        rescue => e
          failures << { game: game, error: e }
          puts "[#{index_str}] FAIL #{game.title.inspect}: #{e.class}: #{e.message}"
        end
      end

      puts ""
      puts "[pito:cover_arts:regenerate] done. #{successes}/#{total} OK, #{failures.size} failed"
      failures.each { |f| puts "  - id=#{f[:game].id} #{f[:game].title.inspect}: #{f[:error].message}" }
    end

    desc "Regenerate the cover master for a single Game by id"
    task :"regenerate:game", [ :id ] => :environment do |_, args|
      id = args.fetch(:id) { abort "usage: bin/rails pito:cover_arts:regenerate:game[ID]" }
      game = Game.find(id)
      target_dir = Pito::AssetsRoot.path("covers", "games", game.id.to_s)
      FileUtils.rm_rf(target_dir) if File.directory?(target_dir)

      path = Game::CoverArt::Normalizer.new(game: game).call
      puts "Game id=#{game.id} #{game.title.inspect}:"
      puts "  cover_image_id: #{game.cover_image_id.inspect}"
      puts "  regenerated:    #{path || '(skipped — no cover_image_id)'}"
    end
  end
end
