# frozen_string_literal: true

# Suggests LIBRARY games a freshly-imported, still-unlinked video probably
# belongs to — one Notification surface, fired at most once per video.
#
# Enqueued by: `Pito::Sync::VideoLibrary#upsert`, right beside the embed-index
# enqueue, ONLY on the `:created` path (a brand-new video, never a resync) —
# see that file's comment for why.
#
# Turn-less (sync/cron context, no live turn to append a scrollback message
# to), so the surface is a `Notification` — never `Pito::Stream::Broadcaster`
# — whose payload lists the ranked candidates as ready-to-run
# `link vid <id> to game <id>` commands (`Pito::Notifications::Source::LinkSuggestion`).
#
# `link_suggested_at` is the once-only marker: stamped here (never by the
# suggester itself, see `Video::GameLinkSuggester`) so a video is only ever
# offered once. A quiet run (no candidates scored) stamps nothing, so a later
# resync/import that finds the same still-unlinked video — with the target
# game imported into the library by then — gets another shot.
class LinkSuggestionJob < ApplicationJob
  queue_as :default

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video
    return if video.video_game_links.exists?
    return if video.link_suggested_at.present?

    suggestions = ::Video::GameLinkSuggester.call(video)
    return if suggestions.empty?

    video.update_column(:link_suggested_at, Time.current)
    ::Pito::Notifications::Source::LinkSuggestion.report!(video:, games: suggestions)
  end
end
