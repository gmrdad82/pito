# frozen_string_literal: true

module Pito
  module Analytics
    # Computes the 1–2 likes-vs-dislikes HEARTS for an analyze scope, ALWAYS over
    # the LIFETIME window (the likes score is a lifetime verdict, independent of the
    # message's shift+space period). Mirrors the job's `groups` model
    # ([[channel, video_ids|:channel], …]) and folds likes/dislikes from the shared
    # `scalars` primitive (Pito::Analytics::Primitives — 0.9.0 Phase 1), so the
    # hearts reuse whatever a glance or analyze already fetched for the scope.
    #
    # Layout (owner 2026-07-01) — ONE heart per level, except vid:
    #   vid     → SUBJECT (the vid's own ratio, red) + CHANNEL heart (purple)
    #   game    → SUBJECT heart only (the linked vids' combined ratio, red) — NO
    #             channel heart (a game spans channels, so it's meaningless here)
    #   channel → CHANNEL heart only (purple)
    #
    # Score = likes / (likes + dislikes) × 100 (YouTube "Likes vs dislikes" %).
    # Returns an Array of heart hashes { score:, color:, likes:, dislikes: } (1 or
    # 2), or nil when there is no rating data (zero likes+dislikes) or every group
    # errors — the cell then falls back to the scaffold "0" display.
    module LikesHearts
      LIFETIME = "lifetime"

      module_function

      # @param groups [Array<[Channel, Array<String>|:channel]>] the job's groups
      # @param level  [String] "vid" | "game" | "channel"
      # @return [Array<Hash>, nil]
      def for(groups:, level:)
        return nil if groups.blank?

        window  = Pito::Analytics::Window.for(LIFETIME, reference_date: Date.current)
        subject = ratio(groups, window)
        return nil unless subject

        case level.to_s
        when "channel"
          # Channel: ONE channel heart only.
          [ heart(subject, :purple) ]
        when "game"
          # Game: ONE heart from the game's linked vids — no channel heart (a game
          # spans channels, so a channel heart is meaningless here) (owner).
          [ heart(subject, :red) ]
        else
          # Vid: TWO hearts — the vid's own ratio + its channel's ratio.
          channel = ratio(whole_channel_groups(groups), window)
          [ heart(subject, :red), (heart(channel, :purple) if channel) ].compact
        end
      end

      # Sum likes/dislikes across the groups over `window` → { likes:, dislikes:,
      # score: } or nil when there are no ratings (or every group errors).
      # Folds from the shared `scalars` primitive (0.9.0 Phase 1) — string-keyed
      # per-subject rows, warm after any glance/analyze touched the scope.
      def ratio(groups, window)
        rows     = Pito::Analytics::Primitives.fetch(groups:, window:, report: "scalars").values
        likes    = rows.sum { |r| r["likes"].to_i }
        dislikes = rows.sum { |r| r["dislikes"].to_i }

        total = likes + dislikes
        return nil if total.zero?

        { likes:, dislikes:, score: (likes.to_f / total * 100).round(1) }
      rescue StandardError => e
        Rails.logger.warn("[Analytics::LikesHearts] #{e.class}: #{e.message}")
        nil
      end

      # Collapse the scope's groups to ONE whole-channel group per distinct channel
      # (videos: nil → channel-wide), for the channel-average heart.
      def whole_channel_groups(groups)
        groups.map { |ch, _| [ ch, :channel ] }.uniq { |ch, _| ch.id }
      end

      def heart(data, color)
        { score: data[:score], color:, likes: data[:likes], dislikes: data[:dislikes] }
      end
    end
  end
end
