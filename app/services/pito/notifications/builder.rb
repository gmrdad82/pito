# Pito::Notifications::Builder — factory for creating Notification rows
# with a consistent category, tweet-style copy constraints (≤ 140 chars,
# no emojis), and a uniform Result value object.
#
# Public API:
#   Builder.build_channel(channel:, message:, kind:, severity: :info, subject: nil)
#     Creates a category=:channel notification. `channel` is a Channel
#     record used to derive the dedup_key and event_payload. `kind` must
#     be a valid Notification.kinds key (e.g. :sync_error, :youtube_reauth_needed).
#     `subject` is an optional polymorphic target (e.g. a Video record).
#
#   Builder.build_game(game:, message:, kind:, severity: :info, subject: nil)
#     Creates a category=:game notification. `game` is a Game record.
#     `kind` must be a valid Notification.kinds key (e.g. :game_release_today).
#
#   Builder.build_system(message:, kind:, severity: :info, subject: nil)
#     Creates a category=:system notification. No user association —
#     system-wide scope. `kind` (e.g. :import_job_completed, :sync_error).
#     `subject` is an optional polymorphic record for context.
#
#   Builder.build_manual(user:, message:, kind:, severity: :info)
#     Creates a category=:manual notification attributed to `user`.
#     `kind` is an explicit Notification.kinds key.
#
# All methods return a Result:
#   result.success?  → true/false
#   result.record    → the persisted Notification (or nil on failure)
#   result.errors    → ActiveModel::Errors-like array of strings
#
# Copy constraints are validated BEFORE persist. If `message` fails the
# tweet-style rules (length > 140 or contains an emoji) the Result is
# returned with `success? false` and an appropriate error message without
# touching the DB.
#
# Dedup keys are derived as "<category>/<subject_type>/<subject_id>/<message_digest>"
# so duplicate builder calls with identical payloads are idempotent (the
# unique partial index on notifications will reject the second insert, and
# `build_*` catches RecordNotUnique and returns the existing record).
#
# Related: Notification model, Pito::Notifications::PayloadBuilder,
#          Pito::Notifications::Scheduler
module Pito
  module Notifications
    class Builder
      # Lightweight result value object. Immutable after construction.
      Result = Data.define(:success, :record, :errors) do
        def success? = success
        def failure? = !success
      end

      EMOJI_PATTERN = /\p{Emoji}/u
      MAX_LENGTH    = 140

      class << self
        # Build a channel-category notification.
        #
        # @param channel    [Channel]  the originating channel record
        # @param message    [String]   tweet-style copy (≤140 chars, no emojis)
        # @param kind       [Symbol]   Notification.kinds key — caller must supply
        #                              the event-specific kind (e.g. :sync_error,
        #                              :youtube_reauth_needed). No default; this is
        #                              intentional so callers stay explicit.
        # @param severity   [Symbol]   :info / :success / :warn / :urgent (default :info)
        # @param subject    [ActiveRecord::Base, nil]  optional context record
        # @return [Result]
        def build_channel(channel:, message:, kind:, severity: :info, subject: nil)
          copy_errors = validate_copy(message)
          return failure(copy_errors) if copy_errors.any?

          attrs = base_attrs(
            category:    :channel,
            message:     message,
            subject:     subject,
            event_type:  "channel_notification",
            payload:     { "channel_id" => channel.id }
          ).merge(kind: kind, severity: severity)
          persist(attrs)
        end

        # Build a game-category notification.
        #
        # @param game       [Game]     the originating game record
        # @param message    [String]   tweet-style copy
        # @param kind       [Symbol]   Notification.kinds key (e.g. :game_release_today,
        #                              :milestone_reached)
        # @param severity   [Symbol]   :info / :success / :warn / :urgent (default :info)
        # @param subject    [ActiveRecord::Base, nil]  optional context record
        # @return [Result]
        def build_game(game:, message:, kind:, severity: :info, subject: nil)
          copy_errors = validate_copy(message)
          return failure(copy_errors) if copy_errors.any?

          attrs = base_attrs(
            category:    :game,
            message:     message,
            subject:     subject,
            event_type:  "game_notification",
            payload:     { "game_id" => game.id }
          ).merge(kind: kind, severity: severity)
          persist(attrs)
        end

        # Build a system-category notification (no user, admin/infra scope).
        #
        # @param message    [String]   tweet-style copy
        # @param kind       [Symbol]   Notification.kinds key (e.g. :import_job_completed,
        #                              :sync_error)
        # @param severity   [Symbol]   :info / :success / :warn / :urgent (default :info)
        # @param subject    [ActiveRecord::Base, nil]  optional context record
        # @return [Result]
        def build_system(message:, kind:, severity: :info, subject: nil)
          copy_errors = validate_copy(message)
          return failure(copy_errors) if copy_errors.any?

          attrs = base_attrs(
            category:    :system,
            message:     message,
            subject:     subject,
            event_type:  "system_notification",
            payload:     {}
          ).merge(kind: kind, severity: severity)
          persist(attrs)
        end

        # Build a manual notification attributed to a specific user.
        #
        # @param user       [User]   the owner/author of the manual entry
        # @param message    [String] tweet-style copy
        # @param kind       [Symbol] Notification.kinds key (e.g. :calendar_entry_firing)
        # @param severity   [Symbol] :info / :success / :warn / :urgent (default :info)
        # @return [Result]
        def build_manual(user:, message:, kind:, severity: :info)
          copy_errors = validate_copy(message)
          return failure(copy_errors) if copy_errors.any?

          attrs = base_attrs(
            category:    :manual,
            message:     message,
            subject:     nil,
            event_type:  "manual_notification",
            payload:     { "user_id" => user.id }
          ).merge(kind: kind, severity: severity, created_by_user: user)
          persist(attrs)
        end

        private

        # Validates tweet-style copy rules.
        # Returns an array of error strings (empty = valid).
        def validate_copy(message)
          errs = []
          if message.blank?
            errs << "message can't be blank"
            return errs
          end
          errs << "message must be 140 characters or fewer" if message.length > MAX_LENGTH
          errs << "message: no emojis allowed"              if message.match?(EMOJI_PATTERN)
          errs
        end

        # Builds the attributes hash common to all categories.
        # `dedup_key` is derived from a stable digest of the payload so
        # identical calls are idempotent.
        def base_attrs(category:, message:, subject:, event_type:, payload:)
          subject_payload = subject ? { "subject_type" => subject.class.name, "subject_id" => subject.id } : {}
          full_payload    = payload.merge(subject_payload)
          digest          = Digest::SHA1.hexdigest("#{category}/#{event_type}/#{message}/#{full_payload.sort.inspect}")[0, 16]

          {
            category:      category,
            title:         message,
            event_type:    event_type,
            severity:      :info,
            fires_at:      Time.current,
            event_payload: full_payload,
            dedup_key:     "builder/#{category}/#{digest}"
          }
        end

        # Attempts to persist a Notification. Handles the idempotency case
        # where a duplicate dedup_key already exists (returns the existing
        # record as a success).
        def persist(attrs)
          notification = Notification.create!(attrs)
          Result.new(success: true, record: notification, errors: [])
        rescue ActiveRecord::RecordNotUnique
          existing = Notification.find_by(dedup_key: attrs[:dedup_key])
          Result.new(success: true, record: existing, errors: [])
        rescue ActiveRecord::RecordInvalid => e
          Result.new(success: false, record: nil, errors: e.record.errors.full_messages)
        end

        def failure(errs)
          Result.new(success: false, record: nil, errors: errs)
        end
      end
    end
  end
end
