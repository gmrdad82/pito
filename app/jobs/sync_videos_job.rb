# frozen_string_literal: true

# Unified chat-initiated YouTube video sync — the single job behind BOTH the
# `sync videos` verb and its `import videos` alias.
#
# Two paths, selected by `video_ids`:
#
#   * Whole-channel (default, `video_ids` empty) — for each scoped channel runs
#     the full `Pito::Sync::VideoLibrary#sync` (imports new/private uploads +
#     reconciles attribute updates and deletions). Channels that need reauth are
#     NOT synced; they get a per-channel reauth line instead.
#   * Targeted (`video_ids` present) — refreshes only the named local videos via
#     `Pito::Sync::VideoLibrary#refresh` (videos.list + upsert, no discovery, no
#     deletion), grouped by channel.
#
# Broadcasts ONE enhanced summary: per-channel `pito.copy.videos.sync_summary`
# lines plus an "All channels" total when more than one channel was synced.
#
# `channel_ids` empty = all channels with a youtube_connection (reauth ones
# included, so they surface a reauth line). `scope_label` is the human-readable
# string used in the turn input text.
class SyncVideosJob < ApplicationJob
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
  end

  def perform(channel_ids, scope_label, conversation_id: nil, video_ids: [])
    return unless conversation_id.present?

    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/sync videos #{scope_label}".strip
    )

    body =
      if Array(video_ids).any?
        targeted_body(video_ids)
      else
        whole_channel_body(channel_ids)
      end

    broadcaster.emit(turn:, kind: :enhanced, payload: { body:, html: true })
    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[SyncVideosJob] failed for scope=#{scope_label}: #{e.class}: #{e.message}")
  end

  private

  # ── Whole-channel sync ─────────────────────────────────────────────────────

  # Full sync of every scoped channel: a `sync_summary` line per healthy channel
  # plus a reauth line for each channel that needs reconnection, then an "All
  # channels" total when more than one channel was actually synced.
  def whole_channel_body(channel_ids)
    channels        = resolve_channels(channel_ids).to_a
    reauth, healthy = channels.partition { |channel| channel.youtube_connection&.needs_reauth? }

    # A manual sync of a known-revoked channel still pings the operator (deduped),
    # so the reauth reminder isn't gated behind the nightly scan.
    reauth.each { |channel| Pito::Notifications::Source::YoutubeReauth.report!(channel.youtube_connection) }

    totals        = Totals.new(imported: 0, updated: 0, deleted: 0)
    healthy_lines = healthy.filter_map do |channel|
      result = safe_sync(channel)
      next unless result

      totals.add(result)
      summary_line(channel.at_handle, result)
    end

    lines = healthy_lines + reauth.map { |channel| reauth_line(channel) }
    return render_body([ I18n.t("pito.jobs.import_videos.summary.nothing_new") ]) if lines.empty?

    lines << summary_line(I18n.t("pito.jobs.import_videos.summary.total_label"), totals) if healthy_lines.size > 1
    render_body(lines)
  end

  def safe_sync(channel)
    ::Pito::Sync::VideoLibrary.new(channel).sync
  rescue StandardError => e
    Rails.logger.error("[SyncVideosJob] channel #{channel.id} sync failed: #{e.class}: #{e.message}")
    nil
  end

  # ── Targeted refresh ───────────────────────────────────────────────────────

  # Refresh only the named local videos, grouped by their channel. One
  # `sync_summary` line per channel, plus an "All channels" total when more than
  # one channel is touched.
  def targeted_body(video_ids)
    videos = ::Video.where(id: video_ids).includes(:channel)

    totals = Totals.new(imported: 0, updated: 0, deleted: 0)
    lines  = videos.group_by(&:channel).filter_map do |channel, channel_videos|
      next unless channel

      youtube_ids = channel_videos.filter_map(&:youtube_video_id)
      result      = safe_refresh(channel, youtube_ids)
      next unless result

      totals.add(result)
      summary_line(channel.at_handle, result)
    end

    return render_body([ I18n.t("pito.jobs.import_videos.summary.nothing_new") ]) if lines.empty?

    lines << summary_line(I18n.t("pito.jobs.import_videos.summary.total_label"), totals) if lines.size > 1
    render_body(lines)
  end

  def safe_refresh(channel, youtube_ids)
    ::Pito::Sync::VideoLibrary.new(channel).refresh(youtube_ids)
  rescue StandardError => e
    Rails.logger.error("[SyncVideosJob] channel #{channel.id} refresh failed: #{e.class}: #{e.message}")
    nil
  end

  # ── Shared helpers ─────────────────────────────────────────────────────────

  # One `pito.copy.videos.sync_summary` line for a label + count source.
  def summary_line(label, counts)
    Pito::Copy.render(
      "pito.copy.videos.sync_summary",
      label:    label,
      imported: counts.imported,
      updated:  counts.updated,
      deleted:  counts.deleted
    )
  end

  def reauth_line(channel)
    Pito::Copy.render(
      "pito.copy.import_videos.per_channel_reauth",
      { handle: channel.at_handle }
    )
  end

  def wrap_line(text)
    %(<div class="text-fg">#{text}</div>)
  end

  # Join wrapped summary lines into the message body, embedding the timestamp
  # slot in the FIRST line so the message's "HH:MM ·" prefix renders inline
  # rather than orphaned on a line above (mirrors ManPage's TS_SLOT use).
  def render_body(lines)
    Array(lines).each_with_index.map { |line, i|
      wrap_line(i.zero? ? "#{Pito::Event::BodyComponent::TS_SLOT}#{line}" : line)
    }.join
  end

  def resolve_channels(channel_ids)
    ids = Array(channel_ids).map(&:to_i).select(&:positive?)
    if ids.empty?
      ::Channel.joins(:youtube_connection).order(:title)
    else
      ::Channel.where(id: ids).order(:title)
    end
  end
end
