# Phase 7.5 — Step 11i (Daily Channel Diff-Check + Resolution).
#
# Apply orchestrator for a `ChannelDiff`. Consumes an open diff +
# a per-field decisions hash + the acting user. In a single
# transaction:
#
#   1. Validate every decision is "pito" or "youtube" and that every
#      field in the diff carries a decision. Reject otherwise.
#   2. For each `accept youtube` field — assign the local column from
#      the YouTube snapshot.
#   3. For each `accept pito` field — call
#      `Youtube::Client#update_channel` with the supported branding
#      subset in one batched PUT (the YouTube API requires read-modify-
#      write on `brandingSettings`; per-call writes against the same
#      resource would race). Handle has its own endpoint
#      (`Youtube::Client#update_handle`); when one is implemented the
#      DiffApply will branch.
#      For title / handle pushes that succeed, append a
#      `ChannelChangeLog` row (locked Q8 — audit narrowed to the two
#      human-identity fields, matching the existing audit table shape).
#   4. Persist the staged channel changes (`save!`).
#   5. Mark the diff resolved: `resolved_at`, `resolved_by_user_id`,
#      `resolution_payload = { field => { decision:, value: } }`.
#
# Per locked Q3 — partial-failure UX: a transaction with rollback on
# the first push failure. Surfaces a clear error code + message so the
# controller can re-render the form with a flash naming the failing
# field. NOTHING is committed when any push fails — "applied N of M;
# rest rolled back; review and retry".
#
# Returns a `Result` struct mirroring `Youtube::VideoDiffApply::Result`
# so the controller / MCP tool can share the same shape.
module Channels
  class DiffApply
    Result = Struct.new(:success, :diff, :error_code, :error_message,
                        :pito_wins_fields, :youtube_wins_fields,
                        :failing_field,
                        keyword_init: true) do
      def success?
        success
      end
    end

    class ValidationError < StandardError; end
    class PushFailure < StandardError
      attr_reader :field, :original
      def initialize(field, original)
        @field = field
        @original = original
        super("push failed for field=#{field}: #{original.message}")
      end
    end

    DECISION_PITO    = "pito".freeze
    DECISION_YOUTUBE = "youtube".freeze

    # Fields where a `accept pito` decision writes a `ChannelChangeLog`
    # audit row (locked Q8). Mirrors `ChannelChangeLog::FIELDS`.
    AUDITED_FIELDS = %w[title handle].freeze

    # Fields the YouTube `channels.update` (`brandingSettings`)
    # endpoint accepts — the existing `Youtube::Client#update_channel`
    # contract.
    BRANDING_PUSH_FIELDS = %w[title description country default_language keywords].freeze

    # `handle` flows through a different endpoint
    # (`Youtube::Client#update_handle`, expected from 11c follow-up
    # research). Until that ships the DiffApply rejects an
    # `accept pito` decision on `handle` with a clear error.
    HANDLE_FIELD = "handle".freeze

    # Fields with no current `accept pito` push path. Selecting "pito"
    # on these surfaces a clean validation error (rather than a silent
    # success that loses the user's value).
    UNSUPPORTED_PITO_FIELDS = %w[
      banner_url avatar_url watermark_url
      watermark_timing watermark_offset_ms
      links
    ].freeze

    def self.call(channel_diff:, decisions:, user: nil, client: nil)
      new(channel_diff: channel_diff, decisions: decisions,
          user: user, client: client).call
    end

    def initialize(channel_diff:, decisions:, user: nil, client: nil)
      @diff = channel_diff
      @channel = channel_diff.channel
      @decisions = (decisions || {}).each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.to_s
      end
      @user = user
      @injected_client = client
    end

    def call
      return already_resolved if @diff.resolved?

      field_diffs = @diff.field_diffs || {}
      diff_fields = field_diffs.keys

      validation_error = validate_decisions(diff_fields)
      return validation_error if validation_error

      pito_fields    = diff_fields.select { |f| @decisions[f] == DECISION_PITO }
      youtube_fields = diff_fields.select { |f| @decisions[f] == DECISION_YOUTUBE }

      unsupported = pito_fields & UNSUPPORTED_PITO_FIELDS
      if unsupported.any?
        return Result.new(success: false, diff: @diff,
                          error_code: "unsupported_pito_field",
                          error_message: "cannot push these fields to youtube " \
                                         "from this surface yet: #{unsupported.join(', ')}.",
                          failing_field: unsupported.first)
      end

      now = Time.current
      resolution_payload = {}

      ActiveRecord::Base.transaction do
        # Stage YouTube-wins on the in-memory channel record.
        youtube_fields.each do |field|
          yt_value = field_diffs.dig(field, "youtube")
          coerced = coerce_for_local_column(field, yt_value)
          @channel.public_send("#{field}=", coerced) if @channel.respond_to?("#{field}=")
          resolution_payload[field] = { "decision" => DECISION_YOUTUBE, "value" => yt_value }
        end

        # Push Pito-wins to YouTube. Branding fields go in one batched
        # PUT (matches the `channels.update` read-modify-write
        # contract); handle has its own endpoint. First failure raises
        # PushFailure and the whole transaction rolls back.
        branding_pito = pito_fields & BRANDING_PUSH_FIELDS
        if branding_pito.any?
          payload = branding_pito.each_with_object({}) do |field, h|
            h[field.to_sym] = field_diffs.dig(field, "pito")
          end
          begin
            push_branding!(payload)
          rescue StandardError => e
            raise PushFailure.new(branding_pito.first, e)
          end
        end

        if pito_fields.include?(HANDLE_FIELD)
          begin
            push_handle!(field_diffs.dig(HANDLE_FIELD, "pito"))
          rescue StandardError => e
            raise PushFailure.new(HANDLE_FIELD, e)
          end
        end

        pito_fields.each do |field|
          pito_value = field_diffs.dig(field, "pito")
          resolution_payload[field] = { "decision" => DECISION_PITO, "value" => pito_value }

          if AUDITED_FIELDS.include?(field)
            ChannelChangeLog.create!(
              channel: @channel,
              field: field,
              old_value: serialize_log_value(field_diffs.dig(field, "youtube")),
              new_value: serialize_log_value(pito_value),
              changed_at: now,
              changed_by_user: @user
            )
            stamp_column = "#{field}_changed_at"
            if @channel.respond_to?("#{stamp_column}=")
              @channel.public_send("#{stamp_column}=", now)
            end
          end
        end

        @channel.save! if @channel.changed?

        @diff.update!(
          resolved_at: now,
          resolved_by_user_id: @user&.id,
          resolution_payload: resolution_payload
        )
      end

      Result.new(
        success: true,
        diff: @diff,
        pito_wins_fields: pito_fields,
        youtube_wins_fields: youtube_fields
      )
    rescue PushFailure => e
      Result.new(success: false, diff: @diff,
                 error_code: error_code_for(e.original),
                 error_message: "could not push #{e.field} to youtube: " \
                                "#{e.original.message}. no changes applied.",
                 failing_field: e.field)
    rescue ValidationError => e
      Result.new(success: false, diff: @diff,
                 error_code: "validation_error", error_message: e.message)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, diff: @diff,
                 error_code: "record_invalid", error_message: e.message)
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
                                         "#{stray.join(', ')}. the diff changed " \
                                         "while you were reviewing; please re-open " \
                                         "the page.")
      end

      nil
    end

    def already_resolved
      Result.new(success: false, diff: @diff,
                 error_code: "already_resolved",
                 error_message: "this diff was already resolved.")
    end

    def push_branding!(payload)
      client = resolve_client
      client.update_channel(@channel, payload)
    end

    # `Youtube::Client#update_handle` is not yet implemented (the
    # surface lands with 11c follow-up research per the parent spec).
    # Until then DiffApply lets tests stub the method on the client
    # double; in production an `accept pito` on `handle` raises
    # NoMethodError → PushFailure → user sees a clear error.
    def push_handle!(value)
      client = resolve_client
      client.update_handle(@channel, value)
    end

    def resolve_client
      @resolved_client ||= begin
        return @injected_client if @injected_client

        connection = @channel.youtube_connection
        raise ValidationError, "no youtube connection on this channel" if connection.nil?
        Youtube::Client.new(connection)
      end
    end

    def coerce_for_local_column(field, value)
      case field
      when "watermark_offset_ms"
        value.nil? ? nil : begin
          Integer(value.to_s)
        rescue ArgumentError, TypeError
          value
        end
      when "links"
        Array(value)
      else
        value
      end
    end

    def serialize_log_value(value)
      case value
      when nil           then nil
      when String        then value
      when Array, Hash   then value.to_json
      else value.to_s
      end
    end

    def error_code_for(error)
      case error
      when Youtube::QuotaExhaustedError then "quota_exhausted"
      when Youtube::AuthRevokedError    then "auth_revoked"
      when Youtube::NeedsReauthError    then "needs_reauth"
      when Youtube::ValidationError     then "youtube_validation"
      when Youtube::NotFoundError       then "youtube_not_found"
      when Youtube::ServerError         then "youtube_server_error"
      when Youtube::TransientError      then "youtube_transient"
      when Youtube::Error               then "youtube_error"
      else "push_failed"
      end
    end
  end
end
