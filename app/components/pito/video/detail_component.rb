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
            when: @video.publish_at.in_time_zone.strftime("%d-%m-%Y %H:%M"),
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

      # Stat counters (views · likes · comms) for Pito::Stats::CountersComponent.
      def stat_counter_metrics
        [
          { key: :views, value: @video.view_count.to_i },
          { key: :likes, value: @video.like_count.to_i },
          { key: :comms, value: @video.comment_count.to_i }
        ]
      end

      def description
        @video.description.presence
      end

      # Returns one Achievement per metric — the one with the highest threshold
      # (the last unlocked in that lane) — ordered by unlocked_at descending
      # so the most recently-advanced lane appears first.
      def top_shinies_per_metric
        @video.achievements
              .group_by(&:metric)
              .values
              .map { |a| a.max_by(&:threshold) }
              .sort_by { |a| -a.unlocked_at.to_i }
      end

      private
    end
  end
end
