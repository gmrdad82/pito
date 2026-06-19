# frozen_string_literal: true

# Imports videos from a connection's YouTube channels into the local Video
# table. Part of the multi-stage /connect flow (stage 2), but also the manual
# `import videos` feedback path: it runs the FULL per-channel sync — new-upload
# discovery (`import_new`) AND reconciliation (`reconcile`) — and reports a
# concise aggregate summary in chat.
#
# Flow:
#   1. For each channel, run `import_new` + `reconcile` via Pito::Sync::VideoLibrary
#   2. Aggregate the Results into connection-wide totals (new / updated / removed)
#   3. Emit enhanced #2 with a sync summary (or a "nothing new" line)
#   4. Resolve thinking #2
#   5. Complete turn (broadcasts pito:done — dots hide)
class ImportVideosJob < ApplicationJob
  queue_as :default

  # Tally of a sync run, summed across channels. Mirrors the count fields of
  # Pito::Sync::VideoLibrary::Result, dropping per-channel titles.
  Totals = Struct.new(:imported, :updated, :deleted, keyword_init: true) do
    def add(result)
      self.imported += result.imported
      self.updated  += result.updated
      self.deleted  += result.deleted
      self
    end

    def empty?
      imported.zero? && updated.zero? && deleted.zero?
    end
  end

  def perform(connection_id, turn_id)
    connection = YoutubeConnection.find_by(id: connection_id)
    turn       = Turn.find_by(id: turn_id)

    return unless connection && turn
    return if turn.completed_at.present?

    conversation = turn.conversation
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)

    channels = Channel.where(youtube_connection_id: connection.id)

    totals        = Totals.new(imported: 0, updated: 0, deleted: 0)
    channel_lines = []

    channels.each do |channel|
      result = sync_channel(channel)
      next unless result

      totals.add(result)
      channel_lines << summary_line(channel.at_handle, result)
    end

    # P4 — linked videos' view counts may have changed; refresh the
    # materialized `views` stat on every affected game.
    enqueue_game_stats_refreshes(channels)

    # Emit enhanced #2 with the aggregate sync summary.
    broadcaster.emit(
      turn:,
      kind:    :enhanced,
      payload: {
        body: summary_body(totals, channel_lines),
        html: true
      }
    )

    # Resolve thinking #2
    broadcaster.resolve_thinking(turn:)

    # Complete turn — dots hide on pito:done
    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    handle_error(turn, e)
    raise
  end

  private

  def handle_error(turn, error)
    return unless turn

    conversation = turn.conversation
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(
      turn:,
      kind:    :error,
      payload: {
        text:   Pito::Copy.render("pito.copy.errors.dispatch_failed"),
        detail: error.message
      }
    )
    broadcaster.resolve_thinking(turn:)
    broadcaster.complete_turn(turn:)
  end

  def enqueue_game_stats_refreshes(channels)
    game_ids = VideoGameLink
      .joins(:video)
      .where(videos: { channel_id: channels.pluck(:id) })
      .distinct
      .pluck(:game_id)

    game_ids.each { |id| GameStatsRefreshJob.perform_later(id) }
  end

  # Run the FULL sync for one channel via `Pito::Sync::VideoLibrary#sync`
  # (new-upload discovery + reconciliation, counts summed across both passes).
  # Returns the combined Result, or nil when the channel has no live connection.
  def sync_channel(channel)
    return nil unless channel.youtube_connection

    result = Pito::Sync::VideoLibrary.new(channel).sync
    channel.touch(:last_synced_at)
    result
  end

  # One `pito.copy.videos.sync_summary` line for a single label + count source.
  def summary_line(label, counts)
    Pito::Copy.render(
      "pito.copy.videos.sync_summary",
      label:    label,
      imported: counts.imported,
      updated:  counts.updated,
      deleted:  counts.deleted
    )
  end

  # Build the enhanced body: a "nothing new" line when nothing changed at all,
  # otherwise the per-channel lines plus an "All channels" total (the total is
  # omitted when there is only one channel, to avoid a duplicate line).
  def summary_body(totals, channel_lines)
    return wrap_line(I18n.t("pito.jobs.import_videos.summary.nothing_new")) if totals.empty?

    lines = channel_lines.dup
    lines << summary_line(I18n.t("pito.jobs.import_videos.summary.total_label"), totals) if channel_lines.size > 1

    lines.map { |line| wrap_line(line) }.join
  end

  def wrap_line(text)
    %(<div class="text-fg">#{text}</div>)
  end
end
