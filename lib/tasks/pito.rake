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
end
