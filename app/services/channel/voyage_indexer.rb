# Phase 35 (2026-05-19) — Voyage embedding for a single Channel.
#
# Mirrors `Bundle::VoyageIndexer` + `Game::VoyageIndexer` for the
# Channel record so the unified search corpus + neighbor-lookup
# surfaces (e.g. `Game::ChannelRecommendation` via the `has_neighbors
# :summary_embedding` declaration on Channel) cover channels alongside
# games and bundles. The flow:
#
#   1. Build the channel-level composite text (title + handle +
#      description + keywords).
#   2. Call `Voyage::Client#embed` for that text (when the API key
#      is configured). Persist the returned 1024-dim vector to
#      `channels.summary_embedding` via `update_column` (skip
#      callbacks — avoid re-firing the Meilisearch reindex /
#      Voyage callback / calendar derivation chain on every embed).
#
# Today vs future text composition:
#
#   Today: channel-level fields only (title, handle, description,
#   keywords). Description and keywords are the dominant signal —
#   the channel's `description` is the long-form "about" blob and
#   `keywords` is the comma-separated topic tag list YouTube
#   surfaces in channel branding settings.
#
#   Future (when /videos returns): centroid of channel-level text +
#   per-video aggregates (top N videos by view-count, each
#   contributing its title + tags + description). This mirrors
#   `Bundle::VoyageIndexer`'s "bundle name + member-games summaries
#   up to MAX_MEMBER_SUMMARIES" composition pattern — collapse the
#   children into a capped aggregate and em-dash-join it onto the
#   parent text. Cap is a knob (likely 5–10 by view-count) to keep
#   the token budget bounded.
#
# Gating: matches `Game::VoyageIndexer` —
# `AppSetting.voyage_configured?` gates the Voyage call. When the
# API key is blank the embedding step is skipped silently (no
# crash, no retry storm). CLAUDE.md locked the per-target
# `voyage_index_*` flag pattern OUT (Phase 29 settings refactor);
# a configured key is the only signal.
#
# Empty inputs: when every component (title + handle + description
# + keywords) is blank we no-op (no Voyage call, nothing to embed).
# A row with only a `title` still indexes — the title alone is
# enough for similarity surfaces to anchor on.
#
# Idempotent on retry: re-running re-embeds and re-writes; the
# pgvector insert replaces the prior value.
class Channel
  class VoyageIndexer
    def self.call(channel)
      new(channel).call
    end

    def initialize(channel)
      @channel = channel
    end

    def call
      return if composite_text.blank?
      return unless AppSetting.voyage_configured?

      embed_and_persist
    end

    private

    def embed_and_persist
      vector = Voyage::Client.new.embed([ composite_text ]).first
      if vector.nil?
        # 2026-05-19 — surface the silent-failure case. The Voyage
        # HTTP client (`Voyage::Client#post_embeddings`) rescues
        # every `StandardError` and returns nil so a transient
        # network blip or a misconfigured key does not crash the
        # job; that hides the failure from operators. Raise so
        # Sidekiq records a visible failure + schedules a retry.
        # Operators can also see the underlying cause in the
        # `[Voyage::Client] embed failed` log line emitted from
        # the client.
        raise "Voyage embedding returned nil for channel ##{@channel.id} " \
              "(api key configured but call failed — see prior log lines)"
      end

      # `update_column` skips validations + callbacks so this write
      # does not re-trigger the `after_save_commit` chain on
      # Channel (Meilisearch reindex, Voyage reindex, calendar
      # derivation). The pgvector column accepts the array directly.
      @channel.update_column(:summary_embedding, vector)
    end

    # Today: channel-level text only — title, handle, description,
    # keywords. Stripped + blank-filtered, em-dash-joined to match the
    # natural visual order operators see on the channel show page and
    # the affordance used elsewhere (Games / Bundles indexers).
    #
    # Future (when /videos returns): wrap this in
    # `[channel_text, video_aggregate_text].compact.join(" — ")`,
    # where `video_aggregate_text` collapses the top N videos by
    # view-count via `videos.top_by_views(MAX_VIDEO_AGGREGATES)
    # .map { |v| [v.title, v.tags, v.description].join(" ") }
    # .join(" — ")`. Cap stays bounded (likely 5–10) to keep token
    # budget under control. See `Bundle::VoyageIndexer
    # #aggregated_member_summaries` for the equivalent pattern on
    # the Bundle side.
    def composite_text
      parts = [ @channel.title, @channel.handle, @channel.description, @channel.keywords ]
      parts.compact.map { |p| p.to_s.strip }.reject(&:blank?).join(" — ")
    end
  end
end
