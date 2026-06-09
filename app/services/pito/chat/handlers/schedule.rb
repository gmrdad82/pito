# frozen_string_literal: true

# Handler for the `schedule video <id|title> <when>` chat verb.
#
# Emits a :confirmation event so the user can confirm before the change
# is applied locally and written through to YouTube via VideoRemoteStatusSync.
#
# == When parsing
#
# The lexer splits `2026-06-15` into [:number "2026"], [:unknown "-"],
# [:number "06"], [:unknown "-"], [:number "15"] — five raw tokens.
# For `2026-06-15 14:30` there are eight tokens (the HH:MM part is
# [:number "14"], [:colon ":"], [:number "30"]).
#
# Supported forms (detected by tail-pattern matching on the raw body_tokens):
#
#   YYYY-MM-DD HH:MM  →  8 tail tokens: N - N - N N : N (where the two date
#                         and time groups are separated by preceded_by_space)
#   YYYY-MM-DD         →  5 tail tokens: N - N - N
#
# Timezone: all parsed times are treated as UTC.
# Invalid calendrical values (e.g. month 99) → Result::Error.
# Publish times in the past → witty Result::Ok error event.
# No new gems required — uses Time.utc directly.
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

        # Detect and extract the <when> date(time) from the TAIL of body tokens.
        # Returns [:ok, Time, ref_tokens] or [:err, Result::Error].
        #
        # Detection patterns (matched against tail token types, where type is :number/:unknown/:colon):
        #   datetime (8 tail): N - N - N  N : N   (space before the HH part)
        #   date     (5 tail): N - N - N
        def extract_when(tokens)
          # Try datetime pattern: tail [N,"-",N,"-",N, N,":",N]
          # with the 6th token having preceded_by_space=true (date vs time separator)
          if tokens.length >= 8
            tail = tokens[-8..]
            if datetime_tail?(tail)
              yr, mo, dy, hh, mm = tail[0].value.to_i, tail[2].value.to_i,
                                   tail[4].value.to_i, tail[5].value.to_i,
                                   tail[7].value.to_i
              t = safe_utc(yr, mo, dy, hh, mm)
              return [ :ok, t, tokens[0..-9] ] if t
            end
          end

          # Try date-only pattern: tail [N,"-",N,"-",N]
          if tokens.length >= 5
            tail = tokens[-5..]
            if date_tail?(tail)
              yr, mo, dy = tail[0].value.to_i, tail[2].value.to_i, tail[4].value.to_i
              t = safe_utc(yr, mo, dy, 0, 0)
              return [ :ok, t, tokens[0..-6] ] if t
            end
          end

          # No recognisable date pattern. If we have more than one token remaining,
          # assume the user intended a date but typed it wrong → bad_when.
          # With just one token there's no way to know ref vs when → bad_when too
          # (better to show the usage hint for <when> than the generic needs_ref).
          [ :err, Pito::Chat::Result::Error.new(message_key: "pito.chat.schedule.bad_when", message_args: {}) ]
        end

        # 8-token datetime tail: N - N - N (preceded_by_space) N : N
        def datetime_tail?(tail)
          number_token?(tail[0]) &&
            dash_token?(tail[1]) &&
            number_token?(tail[2]) &&
            dash_token?(tail[3]) &&
            number_token?(tail[4]) &&
            number_token?(tail[5]) && tail[5].preceded_by_space &&
            colon_token?(tail[6]) &&
            number_token?(tail[7])
        end

        # 5-token date tail: N - N - N
        def date_tail?(tail)
          number_token?(tail[0]) &&
            dash_token?(tail[1]) &&
            number_token?(tail[2]) &&
            dash_token?(tail[3]) &&
            number_token?(tail[4])
        end

        def number_token?(t)
          t.type == :number
        end

        def dash_token?(t)
          t.type == :unknown && t.value == "-"
        end

        def colon_token?(t)
          t.type == :colon
        end

        # Build a UTC Time safely; return nil for invalid calendar values.
        def safe_utc(yr, mo, dy, hh, mm)
          Time.utc(yr, mo, dy, hh, mm)
        rescue ArgumentError
          nil
        end

        def resolve_video(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Video.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Video.find_by("title ILIKE ?", ref)
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
