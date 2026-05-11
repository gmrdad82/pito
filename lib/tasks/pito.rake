# Pito-namespaced one-off maintenance tasks.
#
# These tasks exist for situations where a clean, idempotent CLI surface
# is preferable to a one-shot console statement: anything that ought to
# show up in shell history with a recognizable name, that an operator
# might want to re-run on multiple environments, or that wants a count
# of rows touched printed back.
namespace :pito do
  desc "Delete every Channel whose youtube_connection_id is NULL (legacy " \
       "seed rows). Idempotent — safe to run on any environment."
  task drop_seeded_channels: :environment do
    # The pre-2026-05-10 seed (`db/seeds.rb`) created up to 100 placeholder
    # Channel rows with `youtube_connection_id: nil`. They have been removed
    # from the seed file; this task cleans up environments that ran the old
    # seed at least once. Real channels minted through the OAuth flow always
    # carry a `youtube_connection_id`, so the filter never deletes anything
    # an operator would want to keep.
    scope = Channel.where(youtube_connection_id: nil)
    count = scope.count

    if count.zero?
      puts "no seeded channels to drop."
      next
    end

    # `destroy_all` so the standard `dependent: :destroy` cascade fires for
    # related rows (videos, calendar entries, change logs, etc.). The
    # legacy seed populated those tables, so a bare `delete_all` would
    # leave orphans behind.
    scope.destroy_all

    puts "dropped #{count} seeded channel#{'s' unless count == 1}."
  end

  # Phase 27 follow-up (2026-05-11) — backfill `games.primary_genre_id`
  # for rows that pre-date the column. Idempotent — already-pinned rows
  # are skipped; rows whose pick resolves to `nil` (zero linked genres)
  # stay `nil` (no row touched, no UPDATE issued).
  #
  # Runs `Games::PrimaryGenrePicker#pick` row-by-row and writes via
  # `update_column` so callbacks DON'T fire — the model's
  # `before_save :assign_primary_genre_if_blank` would otherwise do the
  # same work redundantly, and we want a single, auditable write per
  # row. `find_each` keeps memory flat for large installs.
  desc "Backfill games.primary_genre_id for existing rows. Idempotent."
  task backfill_primary_genres: :environment do
    picker  = Games::PrimaryGenrePicker.new
    updated = 0
    skipped = 0
    no_pick = 0

    Game.where(primary_genre_id: nil).find_each do |game|
      pick = picker.pick(game)
      if pick.nil?
        no_pick += 1
        next
      end
      game.update_column(:primary_genre_id, pick.id)
      updated += 1
    end

    Game.where.not(primary_genre_id: nil).find_each { skipped += 1 } if ENV["VERBOSE"] == "1"

    puts "backfilled primary_genre_id on #{updated} game#{'s' unless updated == 1}."
    puts "  #{no_pick} game#{'s' unless no_pick == 1} had no linked genres (left NULL)."
    puts "  (re-run is a no-op — already-pinned rows are skipped.)"
  end
end
