# frozen_string_literal: true

module Pito
  module Analytics
    # Computes the 1–2 likes-vs-dislikes HEARTS for an analyze scope, ALWAYS over
    # the LIFETIME window (the likes score is a lifetime verdict, independent of the
    # message's shift+space period). Mirrors the job's `groups` model
    # ([[channel, video_ids|:channel], …]) and sums likes/dislikes via the same
    # AnalyticsClient.scalars call Pito::Analytics::Scalars uses.
    #
    # Layout (per the locked LIKES spec):
    #   vid / game → SUBJECT heart (the scope's combined ratio, red) + CHANNEL heart
    #                (the whole channel(s)' combined ratio, purple)
    #   channel    → CHANNEL heart only (purple)
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

        if level.to_s == "channel"
          [ heart(subject, :purple) ]
        else
          channel = ratio(whole_channel_groups(groups), window)
          [ heart(subject, :red), (heart(channel, :purple) if channel) ].compact
        end
      end

      # Sum likes/dislikes across the groups over `window` → { likes:, dislikes:,
      # score: } or nil when there are no ratings (or every group errors).
      def ratio(groups, window)
        likes    = 0
        dislikes = 0
        groups.each do |channel, vids|
          ids = vids == :channel ? nil : Array(vids).presence
          row = ::Channel::Youtube::AnalyticsClient
            .new(channel.youtube_connection)
            .scalars(channel_id: channel.youtube_channel_id,
                     start_date: window.start_date, end_date: window.end_date, videos: ids)
          next if row.blank?

          likes    += row[:likes].to_i
          dislikes += row[:dislikes].to_i
        end

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
