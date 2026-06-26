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

      def avatar_attached?
        @channel.avatar.attached?
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

      # Absolute "DD-MM-YYYY HH:MM" last-sync stamp (local zone), or "—" when the
      # channel has never been synced.
      def last_sync_label
        return I18n.t("pito.channel.detail.never_synced") if @channel.last_synced_at.blank?

        @channel.last_synced_at.in_time_zone.strftime("%d-%m-%Y %H:%M")
      end

      # One Achievement per metric — the highest threshold reached in each lane —
      # ordered by most-recently-advanced first. Mirrors the vid/game cards.
      def top_shinies_per_metric
        @channel.achievements
                .group_by(&:metric)
                .values
                .map { |a| a.max_by(&:threshold) }
                .sort_by { |a| -a.unlocked_at.to_i }
      end
    end
  end
end
