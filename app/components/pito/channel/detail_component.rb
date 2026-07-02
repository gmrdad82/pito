# frozen_string_literal: true

module Pito
  module Channel
    # Renders a channel detail card for chat messages — the `show channel @handle`
    # `:system` message. Mirrors Pito::Video::DetailComponent: LEFT column = avatar
    # + hairline + one-line stats counters (Subs · Views · Vids) + Shinies; RIGHT
    # column = kv-table (Handle, Title, Description, Last sync at).
    #
    # NAMESPACE GOTCHA: inside Pito::Channel::*, the bareword `Channel` resolves to
    # the Pito::Channel MODULE. Use the fully-qualified ::Channel for the model — or
    # just receive the record as a param (preferred here).
    class DetailComponent < ViewComponent::Base
      def initialize(channel:, intro: nil)
        @channel = channel
        @intro   = intro
      end

      def avatar_url
        @channel.avatar_variant_url
      rescue StandardError
        nil
      end

      # Small (60×60) avatar variant (:sm) for the kv-table row.
      def avatar_inline_url
        @channel.avatar_inline_url
      rescue StandardError
        nil
      end

      def avatar_attached?
        @channel.avatar.attached?
      end

      def banner_url
        @channel.banner_url
      rescue StandardError
        nil
      end

      def banner_attached?
        @channel.banner.attached?
      end

      # Stat counters (subs · views · vids) for Pito::Stats::CountersComponent.
      # All three are WORD metrics (no icon) so they render "<value> <Word>".
      def stat_counter_metrics
        [
          { key: :subs,  value: @channel.subscriber_count.to_i },
          { key: :views, value: @channel.view_count.to_i },
          { key: :vids,  value: @channel.video_count.to_i }
        ]
      end

      def description
        @channel.description.presence
      end

      # Absolute last-sync stamp via the shared SyncStamp, with the channel's
      # bespoke never-synced copy as the fallback.
      def last_sync_label
        Pito::Formatter::SyncStamp.call(
          @channel.last_synced_at,
          fallback: I18n.t("pito.channel.detail.never_synced")
        )
      end

      # One Achievement per metric — the highest threshold reached in each lane —
      # newest lane first (shared TopShiniesPerMetric; mirrors the other cards).
      def top_shinies_per_metric
        Pito::Achievements::TopShiniesPerMetric.call(@channel.achievements)
      end
    end
  end
end
