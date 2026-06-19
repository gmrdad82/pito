# frozen_string_literal: true

module Pito
  module Schedule
    # Parse the trailing `<when>` phrase of a `schedule <id> <when>` chat command
    # into a concrete publish time, interpreted in the app-local zone (Time.zone).
    #
    # The video-id reference is the LEADING token(s); the `<when>` phrase is the
    # trailing one. We don't know up front how many leading tokens the ref spans
    # (`5`, `# 5`, …), so we scan split points: for each split we reconstruct the
    # trailing tokens back into text (joining values, honoring preceded_by_space)
    # and try to match it against the `<when>` grammar. The smallest split index
    # wins — i.e. the LONGEST trailing phrase that parses — which keeps a bare
    # numeric id as the ref while consuming the whole natural-language tail.
    #
    # == Supported forms
    #
    #   in 30m | in 30 minutes | in 5 min       → Time.current + N minutes
    #   in 1h [from now] | in 2 hours            → Time.current + N hours
    #   in 3 days                                → that calendar date at 09:00
    #   tomorrow                                 → tomorrow 09:00
    #   tomorrow at noon                         → tomorrow 12:00
    #   at 2pm | at 11pm | at 23                 → TODAY at that time
    #   for DD.MM.YYYY HH:MM | for DD-MM-YYYY …  → absolute (accepts . and -)
    #   DD-MM-YYYY [HH:MM] | DD.MM.YYYY [HH:MM]  → absolute (date-only → 09:00)
    #
    # == Timezone contract
    #
    # Relative `in …` forms compute from Time.current. Named/absolute forms build
    # via Time.zone.local so they land in the user's local zone. No UTC conversion
    # happens here — that occurs only at the YouTube API boundary downstream.
    #
    # Invalid calendar values (e.g. month 99) yield nil (no parse).
    class TimeParser
      # Result of a successful parse. `time` is a TimeWithZone in Time.zone;
      # `ref_tokens` are the leading tokens that precede the `<when>` phrase.
      Result = Data.define(:time, :ref_tokens)

      DEFAULT_HOUR = 9 # date-only / named-day forms default to 09:00 local

      # in <n> <unit> [from now]
      RELATIVE = /\Ain\s+(\d+)\s*(minutes?|mins?|m|hours?|hrs?|hr|h|days?|d)(?:\s+from\s+now)?\z/
      # tomorrow [at <time-of-day>]
      TOMORROW = /\Atomorrow(?:\s+at\s+(.+))?\z/
      # at <time-of-day>
      NAMED_AT = /\Aat\s+(.+)\z/
      # [for] DD<sep>MM<sep>YYYY [HH:MM], sep is "." or "-"
      DATE = /\A(?:for\s+)?(\d{1,2})[.\-](\d{1,2})[.\-](\d{4})(?:\s+(\d{1,2}):(\d{2}))?\z/

      def self.call(tokens, now: Time.current)
        new(tokens, now:).call
      end

      def initialize(tokens, now: Time.current)
        @tokens = tokens.reject { |t| t.type == :eof }
        @now = now
      end

      # Returns a Result, or nil when the tail doesn't parse as a `<when>`.
      def call
        (1...@tokens.length).each do |i|
          when_tokens = @tokens[i..]
          next if when_tokens.empty?

          time = parse_phrase(reconstruct(when_tokens))
          return Result.new(time:, ref_tokens: @tokens[0...i]) if time
        end
        nil
      end

      private

      # Join token values back into text, inserting a single space before any
      # token that was preceded by whitespace in the source (skip the first).
      def reconstruct(tokens)
        tokens.each_with_index.map do |t, i|
          prefix = (i.positive? && t.preceded_by_space) ? " " : ""
          "#{prefix}#{t.value}"
        end.join
      end

      def parse_phrase(raw)
        phrase = raw.strip.downcase.gsub(/\s+/, " ")
        return nil if phrase.empty?

        if (m = RELATIVE.match(phrase))
          relative_time(m[1].to_i, m[2])
        elsif (m = TOMORROW.match(phrase))
          tomorrow_time(m[1])
        elsif (m = NAMED_AT.match(phrase))
          at_today(m[1])
        elsif (m = DATE.match(phrase))
          date_time(m)
        end
      rescue ArgumentError
        nil # invalid calendar values (e.g. month 99)
      end

      def relative_time(count, unit)
        case unit
        when /\Am/ then @now + count.minutes
        when /\Ah/ then @now + count.hours
        when /\Ad/ then at_date(@now.to_date + count, DEFAULT_HOUR, 0)
        end
      end

      def tomorrow_time(time_of_day)
        date = @now.to_date + 1
        return at_date(date, DEFAULT_HOUR, 0) if time_of_day.nil?

        hour_minute = parse_time_of_day(time_of_day)
        hour_minute && at_date(date, hour_minute[0], hour_minute[1])
      end

      def at_today(time_of_day)
        hour_minute = parse_time_of_day(time_of_day)
        hour_minute && at_date(@now.to_date, hour_minute[0], hour_minute[1])
      end

      def date_time(match)
        day, month, year = match[1].to_i, match[2].to_i, match[3].to_i
        hour = match[4] ? match[4].to_i : DEFAULT_HOUR
        minute = match[5] ? match[5].to_i : 0
        Time.zone.local(year, month, day, hour, minute)
      end

      # "noon" | "midnight" | "2pm" | "2 pm" | "23" → [hour, minute] or nil.
      def parse_time_of_day(str)
        case str
        when "noon"     then [ 12, 0 ]
        when "midnight" then [ 0, 0 ]
        when /\A(\d{1,2})\s*(am|pm)\z/
          hour = Regexp.last_match(1).to_i
          return nil unless hour.between?(1, 12)

          hour %= 12
          hour += 12 if Regexp.last_match(2) == "pm"
          [ hour, 0 ]
        when /\A(\d{1,2})\z/
          hour = Regexp.last_match(1).to_i
          hour.between?(0, 23) ? [ hour, 0 ] : nil
        end
      end

      def at_date(date, hour, minute)
        Time.zone.local(date.year, date.month, date.day, hour, minute)
      end
    end
  end
end
