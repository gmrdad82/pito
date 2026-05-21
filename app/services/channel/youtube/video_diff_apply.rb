# Phase 23 — Step 23c (Video Sync + Diff Dialog) — apply orchestrator.
#
# Consumes an open `VideoDiff` + a per-field decisions hash + the
# acting user. In a single transaction:
#
#   1. Validate every decision is `"pito"` or `"youtube"` and that
#      every field carries a decision. Reject with a `ValidationError`
#      otherwise.
#   2. For each `accept youtube` field — overwrite the Pito column
#      from the YouTube snapshot value stored on `VideoDiff#payload`.
#   3. For each `accept pito` field — call `Channel::Youtube::VideosReader` for
#      the fresh API snapshot (1 unit) and then
#      `Channel::Youtube::VideosClient#update_video(video, fresh:, fields: ...)`
#      (50 units) with the set of Pito-wins fields. The local columns
#      stay as they are (Pito-side already carries the desired value).
#   4. On every applied change (in either direction), append a
#      `VideoChangeLog` row with `source: pito_apply` or
#      `source: youtube_pull` accordingly. The log row is created
#      AFTER the column update so `changed_at` aligns with the apply
#      timestamp.
#   5. Stamp `video.last_diff_checked_at = Time.current` and
#      `video_diff.resolved_at = Time.current`,
#      `resolved_by_user_id = current_user.id`,
#      `resolution_payload = decisions`.
#   6. If `title` was Pito-wins applied, stamp
#      `video.title_changed_at = Time.current` (Q1 — inert flag,
#      kept for audit).
#
# The transaction rolls back if the YouTube push fails, so the local
# row and the audit log stay consistent with the remote state.
#
# Returns a Result struct: `success?` true + the resolved diff on
# success; `success?` false + an error code + message on failure.
# Display-only fields default to YouTube on the form (per spec) and
# the apply path rejects `accept pito` on display-only fields with a
# clear error rather than silently doing nothing.
class Channel
  module Youtube
    class VideoDiffApply
      Result = Struct.new(:success, :diff, :error_code, :error_message,
                          :pito_wins_fields, :youtube_wins_fields,
                          keyword_init: true) do
        def success?
          success
        end
      end

      class ValidationError < StandardError; end

      DECISION_PITO    = "pito".freeze
      DECISION_YOUTUBE = "youtube".freeze

      def self.call(video_diff:, decisions:, user: nil, reader: nil, client: nil)
        new(video_diff: video_diff, decisions: decisions, user: user,
            reader: reader, client: client).call
      end

      def initialize(video_diff:, decisions:, user: nil, reader: nil, client: nil)
        @diff = video_diff
        @video = video_diff.video
        @decisions = (decisions || {}).each_with_object({}) do |(k, v), h|
          h[k.to_s] = v.to_s
        end
        @user = user
        @injected_reader = reader
        @injected_client = client
      end

      def call
        return already_resolved if @diff.resolved?

        payload = @diff.payload || {}
        diff_fields = payload.keys

        validation_error = validate_decisions(diff_fields)
        return validation_error if validation_error

        pito_fields    = diff_fields.select { |f| @decisions[f] == DECISION_PITO }
        youtube_fields = diff_fields.select { |f| @decisions[f] == DECISION_YOUTUBE }

        now = Time.current

        ActiveRecord::Base.transaction do
          # Apply YouTube-wins first — purely local column writes.
          youtube_fields.each do |field|
            apply_youtube_wins!(field, payload[field], now: now)
          end

          # If any Pito-wins field is in the writable set, push to
          # YouTube. The push happens AFTER the local YouTube-wins
          # column writes so the read-modify-write base snapshot is
          # whatever YouTube currently holds — `fields:` limits the
          # overlay to only the Pito-wins fields, so the YouTube-wins
          # local writes (which already match YouTube) don't fight the
          # request payload.
          if pito_fields.any?
            writable_pito_fields = pito_fields & Channel::Youtube::DiffComputer::WRITABLE_FIELDS

            if writable_pito_fields.size != pito_fields.size
              raise ValidationError, "cannot accept pito on display-only fields: " \
                                     "#{(pito_fields - writable_pito_fields).join(', ')}"
            end

            push_to_youtube!(writable_pito_fields)

            writable_pito_fields.each do |field|
              log_change!(field, source: :pito_apply,
                          old_value: payload.dig(field, "youtube"),
                          new_value: payload.dig(field, "pito"),
                          at: now)
            end

            if writable_pito_fields.include?("title")
              @video.update_columns(title_changed_at: now)
            end
          end

          @diff.update!(
            resolved_at: now,
            resolution_payload: @decisions,
            resolved_by_user_id: @user&.id
          )
          @video.update_columns(last_diff_checked_at: now)
        end

        Result.new(
          success: true,
          diff: @diff,
          pito_wins_fields: pito_fields,
          youtube_wins_fields: youtube_fields
        )
      rescue ValidationError => e
        Result.new(success: false, diff: @diff,
                   error_code: "validation_error", error_message: e.message)
      rescue Channel::Youtube::QuotaExhaustedError => e
        Result.new(success: false, diff: @diff,
                   error_code: "quota_exhausted", error_message: e.message)
      rescue Channel::Youtube::AuthRevokedError => e
        Result.new(success: false, diff: @diff,
                   error_code: "auth_revoked", error_message: e.message)
      rescue Channel::Youtube::ValidationError => e
        Result.new(success: false, diff: @diff,
                   error_code: "youtube_validation", error_message: e.message)
      rescue Channel::Youtube::NotFoundError => e
        Result.new(success: false, diff: @diff,
                   error_code: "youtube_not_found", error_message: e.message)
      rescue Channel::Youtube::ServerError => e
        Result.new(success: false, diff: @diff,
                   error_code: "youtube_server_error", error_message: e.message)
      end

      private

      def validate_decisions(diff_fields)
        missing = diff_fields.reject { |f| @decisions.key?(f) }
        if missing.any?
          return Result.new(success: false, diff: @diff,
                            error_code: "missing_decisions",
                            error_message: "no decision for fields: #{missing.join(', ')}")
        end

        bad = @decisions.reject { |_, v| [ DECISION_PITO, DECISION_YOUTUBE ].include?(v) }
        if bad.any?
          return Result.new(success: false, diff: @diff,
                            error_code: "invalid_decision",
                            error_message: "decision must be 'pito' or 'youtube' for: " \
                                           "#{bad.keys.join(', ')}")
        end

        stray = @decisions.keys - diff_fields
        if stray.any?
          return Result.new(success: false, diff: @diff,
                            error_code: "stale_diff",
                            error_message: "decision references fields not in diff: " \
                                           "#{stray.join(', ')}")
        end

        nil
      end

      def already_resolved
        Result.new(success: false, diff: @diff,
                   error_code: "already_resolved",
                   error_message: "diff is already resolved")
      end

      def apply_youtube_wins!(field, pair, now:)
        yt_value = pair.is_a?(Hash) ? pair["youtube"] : nil
        pito_old = pair.is_a?(Hash) ? pair["pito"]    : @video.public_send(field)

        coerced_value = coerce_for_local_column(field, yt_value)
        @video.update_columns(field => coerced_value)

        log_change!(field, source: :youtube_pull,
                    old_value: pito_old, new_value: yt_value,
                    at: now)
      end

      # Coerce JSON-shaped YouTube values into the right Ruby types for
      # the local column. Counters arrive as strings; times as ISO 8601
      # strings; booleans pass through.
      def coerce_for_local_column(field, value)
        case field
        when *%w[view_count like_count comment_count duration_seconds]
          value.nil? ? nil : Integer(value.to_s)
        when *%w[publish_at published_at]
          value.blank? ? nil : Time.iso8601(value.to_s)
        when "tags"
          Array(value)
        when "privacy_status"
          # Stored as integer-backed enum; the model accepts the string
          # via the enum mapping.
          value.to_s
        else
          value
        end
      rescue ArgumentError
        value
      end

      def push_to_youtube!(writable_pito_fields)
        connection = @video.channel.youtube_connection
        raise ValidationError, "no youtube connection on this video's channel" if connection.nil?
        raise ValidationError, "youtube connection needs re-auth" if connection.needs_reauth?

        reader = @injected_reader || Channel::Youtube::VideosReader.new(connection)
        client = @injected_client || Channel::Youtube::VideosClient.new(connection)

        fresh = reader.read_video(@video)
        client.update_video(@video, fresh: fresh, fields: writable_pito_fields.map(&:to_sym))
      end

      def log_change!(field, source:, old_value:, new_value:, at:)
        VideoChangeLog.create!(
          video: @video,
          field: field,
          old_value: serialize_log_value(old_value),
          new_value: serialize_log_value(new_value),
          source: source,
          changed_at: at,
          changed_by_user_id: @user&.id
        )
      end

      def serialize_log_value(value)
        case value
        when nil      then nil
        when String   then value
        when Array, Hash then value.to_json
        else value.to_s
        end
      end
    end
  end
end
