# Phase 23 — Step 23a (Video Sync + Diff Dialog).
#
# Pure-function service. Compares a Pito-side `Video` to a YouTube-side
# `videos.list` response payload (snake_case symbolized Hash from
# `Channel::Youtube::Client#videos_list` / `Channel::Youtube::VideosReader#read_video`)
# and returns the differing fields as
#
#   { "field" => { "pito" => <pito_value>, "youtube" => <yt_value> } }
#
# The hash is always String-keyed (matches the jsonb shape stored on
# `VideoDiff#payload`).
#
# Tolerates type mismatches gracefully:
#   - YouTube returns counts as strings; the computer coerces both
#     sides to integers before comparison so a "1000" vs 1000 mismatch
#     never surfaces as a phantom diff.
#   - `tags` is an order-insensitive sorted-set comparison (YouTube
#     sometimes returns tags in a different order than the upload
#     order; that's not a real diff).
#   - Missing keys on either side are tolerated — a YouTube response
#     that omits `statistics` (e.g., a deleted video) collapses to
#     "no diff on the missing fields".
#   - nil-vs-blank-string is collapsed: nil and "" are treated as the
#     same value to avoid noisy diffs on `description` etc.
#
# Only the diff-resolvable field set (see `DIFF_RESOLVABLE_FIELDS`) is
# compared. Fields not in the set are ignored even if their values
# differ.
class Channel
  module Youtube
    class DiffComputer
      # The full field set the diff dialog can surface. Split into
      # writable (`accept pito` pushes to YouTube) and display-only
      # (`accept pito` is disabled; only `accept youtube` makes sense).
      # The apply orchestrator gates Pito-wins on `WRITABLE_FIELDS`
      # membership.
      WRITABLE_FIELDS = %w[
        title description tags category_id
        privacy_status publish_at
        self_declared_made_for_kids contains_synthetic_media
        embeddable public_stats_viewable
      ].freeze

      DISPLAY_ONLY_FIELDS = %w[
        made_for_kids_effective
        view_count like_count comment_count
        duration_seconds published_at
        thumbnail_url
      ].freeze

      DIFF_RESOLVABLE_FIELDS = (WRITABLE_FIELDS + DISPLAY_ONLY_FIELDS).freeze

      INTEGER_FIELDS = %w[
        view_count like_count comment_count duration_seconds
      ].freeze

      BOOLEAN_FIELDS = %w[
        self_declared_made_for_kids contains_synthetic_media
        embeddable public_stats_viewable made_for_kids_effective
      ].freeze

      TIME_FIELDS = %w[publish_at published_at].freeze

      def self.call(video, payload)
        new(video, payload).call
      end

      def initialize(video, payload)
        @video = video
        @payload = payload || {}
      end

      def call
        DIFF_RESOLVABLE_FIELDS.each_with_object({}) do |field, diff|
          pito_value = pito_side(field)
          youtube_value = youtube_side(field)

          next if values_equivalent?(field, pito_value, youtube_value)

          diff[field] = {
            "pito"    => normalize_for_storage(pito_value),
            "youtube" => normalize_for_storage(youtube_value)
          }
        end
      end

      private

      def pito_side(field)
        case field
        when "publish_at", "published_at"
          @video.public_send(field)
        when "duration_seconds"
          @video.duration_seconds
        else
          @video.public_send(field) if @video.respond_to?(field)
        end
      end

      def youtube_side(field)
        case field
        when "title", "description", "tags", "category_id", "thumbnail_url"
          from_snippet(field)
        when "published_at"
          from_snippet("published_at")
        when "privacy_status", "publish_at", "embeddable",
             "public_stats_viewable", "self_declared_made_for_kids",
             "contains_synthetic_media", "made_for_kids_effective"
          from_status(field)
        when "view_count", "like_count", "comment_count"
          from_statistics(field)
        when "duration_seconds"
          from_content_details_duration
        end
      end

      def from_snippet(field)
        snippet = @payload[:snippet] || @payload["snippet"] || {}
        case field
        when "title"         then read_indifferent(snippet, :title)
        when "description"   then read_indifferent(snippet, :description)
        when "tags"          then Array(read_indifferent(snippet, :tags))
        when "category_id"   then read_indifferent(snippet, :category_id) ||
                                  read_indifferent(snippet, :categoryId)
        when "thumbnail_url" then extract_thumbnail(snippet)
        when "published_at"  then read_indifferent(snippet, :published_at) ||
                                  read_indifferent(snippet, :publishedAt)
        end
      end

      def from_status(field)
        status = @payload[:status] || @payload["status"] || {}
        case field
        when "privacy_status"
          read_indifferent(status, :privacy_status) ||
            read_indifferent(status, :privacyStatus)
        when "publish_at"
          read_indifferent(status, :publish_at) ||
            read_indifferent(status, :publishAt)
        when "embeddable"
          read_indifferent(status, :embeddable)
        when "public_stats_viewable"
          read_indifferent(status, :public_stats_viewable) ||
            read_indifferent(status, :publicStatsViewable)
        when "self_declared_made_for_kids"
          read_indifferent(status, :self_declared_made_for_kids) ||
            read_indifferent(status, :selfDeclaredMadeForKids)
        when "contains_synthetic_media"
          read_indifferent(status, :contains_synthetic_media) ||
            read_indifferent(status, :containsSyntheticMedia)
        when "made_for_kids_effective"
          # YouTube exposes this as `madeForKids` (no `_effective` suffix).
          v = read_indifferent(status, :made_for_kids)
          v.nil? ? read_indifferent(status, :madeForKids) : v
        end
      end

      def from_statistics(field)
        stats = @payload[:statistics] || @payload["statistics"] || {}
        case field
        when "view_count"
          read_indifferent(stats, :view_count) || read_indifferent(stats, :viewCount)
        when "like_count"
          read_indifferent(stats, :like_count) || read_indifferent(stats, :likeCount)
        when "comment_count"
          read_indifferent(stats, :comment_count) || read_indifferent(stats, :commentCount)
        end
      end

      # YouTube's `contentDetails.duration` is an ISO 8601 duration
      # ("PT4M13S"). Convert to seconds; tolerate `nil` and malformed
      # input by returning nil (which collapses to "no diff" via
      # `values_equivalent?`).
      def from_content_details_duration
        details = @payload[:content_details] || @payload["content_details"] ||
                  @payload[:contentDetails] || @payload["contentDetails"] || {}
        iso = read_indifferent(details, :duration)
        return nil if iso.blank?
        ActiveSupport::Duration.parse(iso.to_s).to_i
      rescue ArgumentError, TypeError
        nil
      end

      def extract_thumbnail(snippet)
        thumbnails = read_indifferent(snippet, :thumbnails)
        return nil if thumbnails.blank?

        %i[maxres standard high medium default].each do |tier|
          tier_hash = read_indifferent(thumbnails, tier)
          url = read_indifferent(tier_hash, :url) if tier_hash.is_a?(Hash)
          return url if url.present?
        end
        nil
      end

      def read_indifferent(hash, key)
        return nil unless hash.is_a?(Hash)
        return hash[key] if hash.key?(key)
        return hash[key.to_s] if hash.key?(key.to_s)
        return hash[key.to_sym] if hash.key?(key.to_sym)
        nil
      end

      # Compare values after type-coercion + nil/blank collapse.
      def values_equivalent?(field, a, b)
        case field
        when "tags"
          Array(a).map(&:to_s).sort == Array(b).map(&:to_s).sort
        when *INTEGER_FIELDS
          coerce_integer(a) == coerce_integer(b)
        when *BOOLEAN_FIELDS
          coerce_bool(a) == coerce_bool(b)
        when *TIME_FIELDS
          coerce_time(a) == coerce_time(b)
        else
          coerce_string(a) == coerce_string(b)
        end
      end

      def coerce_integer(v)
        return nil if v.nil? || v.to_s.strip.empty?
        Integer(v.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def coerce_bool(v)
        return nil if v.nil?
        return v if v == true || v == false
        case v.to_s.downcase
        when "true", "yes", "1" then true
        when "false", "no", "0" then false
        else v
        end
      end

      def coerce_time(v)
        return nil if v.nil? || v.to_s.strip.empty?
        return v.utc.iso8601 if v.respond_to?(:utc)
        Time.iso8601(v.to_s).utc.iso8601
      rescue ArgumentError, TypeError
        nil
      end

      def coerce_string(v)
        s = v.is_a?(Array) ? v : v.to_s
        return nil if s.respond_to?(:empty?) && s.empty?
        s
      end

      # Serialize a Ruby value into a jsonb-safe form for the
      # `VideoDiff#payload` storage. Times become ISO 8601 strings;
      # arrays / hashes pass through; everything else passes through.
      def normalize_for_storage(v)
        case v
        when Time, DateTime then v.utc.iso8601
        when ActiveSupport::TimeWithZone then v.utc.iso8601
        else v
        end
      end
    end
  end
end
