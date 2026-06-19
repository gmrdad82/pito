# frozen_string_literal: true

# Handler for the `schedule video <id> <when>` chat verb.
#
# Emits a :confirmation event so the user can confirm before the change
# is applied locally and written through to YouTube via VideoRemoteStatusSync.
#
# == When parsing
#
# The video-id reference is the LEADING token(s); the `<when>` phrase is the
# trailing one. Parsing of the `<when>` phrase is delegated to
# `Pito::Schedule::TimeParser`, which recognises both absolute dates
# (`DD-MM-YYYY [HH:MM]`, `.` or `-` separators, optional `for` prefix) and
# natural-language forms (`in 30m`, `in 2 hours`, `in 3 days`, `tomorrow`,
# `tomorrow at noon`, `at 2pm`, `at 23`).
#
# Timezone: parsed times are interpreted in the app local zone (Time.zone)
# for named/absolute forms, and relative to Time.current for `in …` forms.
# UTC conversion happens only at the YouTube API boundary.
# Invalid calendrical values (e.g. month 99) → Result::Error.
# Publish times in the past → witty Result::Ok error event.
# Times under 30 minutes away → too_soon error.
# No new gems required.
module Pito
  module Chat
    module Handlers
      class Schedule < Pito::Chat::Handler
        self.verb = :schedule
        self.description_key = "pito.chat.schedule.descriptions.schedule"

        NOUN_FILLERS = %w[video videos].freeze

        def call
          body = message.body_tokens.reject { |t| NOUN_FILLERS.include?(t.value.to_s.downcase) }
          return needs_ref if body.empty?

          when_result = extract_when(body)
          # when_result is either [:ok, Time, ref_tokens] or [:err, Result::Error]
          if when_result[0] == :err
            return when_result[1]
          end

          _, publish_time, ref_tokens = when_result

          ref = ref_tokens.map(&:value).join(" ").strip
          return needs_ref if ref.blank?

          video = resolve_video(ref)
          return not_found(ref) unless video

          if publish_time <= Time.current
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system,
                payload: Pito::MessageBuilder::Text.call("pito.copy.videos.schedule_in_past", title: video.title) }
            ])
          end

          if publish_time < 30.minutes.from_now
            return Pito::Chat::Result::Error.new(message_key: "pito.chat.schedule.too_soon", message_args: {})
          end

          Pito::Chat::Result::Ok.new(events: [
            { kind: :confirmation,
              payload: Pito::MessageBuilder::Video::ScheduleConfirmation.call(
                video,
                conversation: conversation,
                when: publish_time
              ) }
          ])
        end

        private

        # Extract the <when> from the body tokens via Pito::Schedule::TimeParser.
        # Returns [:ok, Time, ref_tokens] or [:err, Result::Error].
        #
        # The ref is the LEADING token(s); the <when> is the trailing phrase.
        # See Pito::Schedule::TimeParser for the supported <when> grammar.
        def extract_when(tokens)
          result = Pito::Schedule::TimeParser.call(tokens)
          return [ :ok, result.time, result.ref_tokens ] if result

          # No recognisable <when>. Surface the usage hint for <when>.
          [ :err, Pito::Chat::Result::Error.new(message_key: "pito.chat.schedule.bad_when", message_args: {}) ]
        end

        def resolve_video(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Video.find_by(id: id) if id.match?(/\A\d+\z/)

          nil
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.schedule.needs_ref", message_args: {})
        end

        def not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end
      end
    end
  end
end
