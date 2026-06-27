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

        NOUN_FILLERS = %w[vid vids video videos].freeze

        SLATE_KEYWORD = "slate"

        def call
          body = message.body_tokens.reject { |t| NOUN_FILLERS.include?(t.value.to_s.downcase) }
          # On a video-card reply (`#<handle> schedule <when>`) the source video IS
          # the target, so no id is typed. Prepend the card's id so the rest of the
          # body parses as the <when> through the normal ref-leading flow.
          body = prepend_follow_up_ref(body)
          return needs_ref if body.empty?

          # `schedule <id> slate` (or a reply `#<h> schedule slate`) → the
          # upcoming-schedule planning view rather than the schedule-a-time flow.
          return slate(body) if body.last&.value.to_s.downcase == SLATE_KEYWORD

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

        # On a follow-up reply with no typed numeric id, prepend the source card's
        # `video_id` as a synthetic leading token so the existing ref-leading parse
        # targets that video. A typed id, or a list reply with no single
        # `video_id`, is left untouched.
        def prepend_follow_up_ref(body)
          return body unless follow_up?
          return body if body.empty?

          first = body.first.value.to_s.sub(/\A#\s*/, "")
          return body if first.match?(/\A\d+\z/)

          id = follow_up.source_event.payload.with_indifferent_access[:video_id]
          return body if id.blank?

          synthetic = Pito::Lex::Token.new(type: :word, value: id.to_s, position: -1, preceded_by_space: false)
          [ synthetic ] + body
        end

        # `schedule <id> slate` — render the upcoming-schedule planner, obeying the
        # conversation's channel scope (shift+tab) + stats period (shift+space) and
        # excluding the reference vid (the leading id, or the source vid on a reply).
        def slate(body)
          events = Pito::MessageBuilder::Video::Slate.call(
            exclude_id:    slate_exclude_id(body[0...-1]),
            channel_scope: channel.presence || conversation.scope_channel,
            period:        conversation.stats_period,
            conversation:  conversation
          )
          Pito::Chat::Result::Ok.new(events: events)
        end

        # The vid id to exclude from the slate: the typed leading ref, or — on a
        # reply with no id — the source video the reply is anchored to.
        def slate_exclude_id(ref_tokens)
          ref = ref_tokens.map(&:value).join(" ").strip
          return resolve_video(ref)&.id if ref.present?
          return follow_up.source_event.payload.with_indifferent_access[:video_id] if follow_up?

          nil
        end

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
