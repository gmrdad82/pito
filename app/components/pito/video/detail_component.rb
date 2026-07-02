# frozen_string_literal: true

module Pito
  module Video
    # Renders a full video detail card for use in chat messages.
    #
    # NAMESPACE GOTCHA: inside Pito::Video::*, the bareword `Video` resolves to
    # the Pito::Video MODULE. Use the fully-qualified ::Video constant to reference
    # the model — or simply receive the record as a param (preferred here).
    class DetailComponent < ViewComponent::Base
      def initialize(video:, intro: nil)
        @video = video
        @intro = intro
      end

      def thumbnail_url
        @video.thumbnail_variant_url
      rescue StandardError
        nil
      end

      def thumbnail_attached?
        @video.thumbnail.attached?
      end

      def tags_label
        tags = Array(@video.tags).reject(&:blank?)
        tags.join(", ").presence
      end

      def category_label
        @video.category_name.presence
      end

      def privacy_label
        if @video.publish_at.present? && @video.publish_at > Time.current
          return I18n.t(
            "pito.video.detail.scheduled_for",
            when: Pito::Formatter::SyncStamp.call(@video.publish_at),
            default: "Scheduled for %{when}"
          )
        end

        return nil if @video.privacy_status.blank?

        I18n.t("pito.video.detail.privacy_status.#{@video.privacy_status}", default: @video.privacy_status.to_s.capitalize)
      end

      # Format duration via the shared Pito::Formatter::Duration (DD:HH:MM:SS,
      # leading zero-units trimmed).
      def duration_label
        Pito::Formatter::Duration.call(@video.duration_seconds)
      end

      # Stat counters (views · likes · comments) for Pito::Stats::CountersComponent.
      def stat_counter_metrics
        [
          { key: :views,    value: @video.view_count.to_i },
          { key: :likes,    value: @video.like_count.to_i },
          { key: :comments, value: @video.comment_count.to_i }
        ]
      end

      def description
        @video.description.presence
      end

      # Absolute last-sync stamp via the shared SyncStamp; "—" when never synced.
      def last_sync_label
        Pito::Formatter::SyncStamp.call(@video.last_synced_at)
      end

      # One Achievement per metric — the highest threshold reached in each lane —
      # newest lane first (shared TopShiniesPerMetric; mirrors the other cards).
      def top_shinies_per_metric
        Pito::Achievements::TopShiniesPerMetric.call(@video.achievements)
      end

      private
    end
  end
end
