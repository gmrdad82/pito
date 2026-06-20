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
    # Every named/date form takes an optional trailing "[at] <time-of-day>"; with
    # none it defaults to 09:00 (DEFAULT_HOUR). <time-of-day> is one of:
    # noon | midnight | night | 2pm | 3:10am | 23 | 15:30.
    #
    #   in 30m | in 30 minutes | in 5 min        → Time.current + N minutes
    #   in 1h [from now] | in 2 hours             → Time.current + N hours
    #   in 3 days                                 → that calendar date at 09:00
    #   at 2pm | at 3:10am | at 23 | at 15:30      → TODAY at that time
    #   today [at ...] | today at 3am             → today (bare → 09:00)
    #   tomorrow [at ...] | tomorrow night        → tomorrow
    #   <weekday> [at ...]                        → that weekday THIS calendar week
    #   next <weekday> [at ...]                   → that weekday NEXT calendar week
    #   next week [at ...]                        → Monday of next week
    #   next month [at ...]                       → 1st of next month
    #   N days from now | N weeks from now [at …]  → relative calendar date
    #   for DD.MM.YYYY HH:MM | DD-MM-YYYY [HH:MM]  → absolute (accepts . and -)
    #
    # A bare weekday already past in the current week resolves to its past date —
    # the caller's past / too-soon guards reject it; we never roll forward.
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

      DEFAULT_HOUR = 9  # date-only / named-day forms default to 09:00 local
      NIGHT_HOUR = 21   # "night" → 21:00 local

      # Weekday name (and common abbreviations) → canonical symbol.
      WEEKDAYS = {
        "monday" => :monday, "mon" => :monday,
        "tuesday" => :tuesday, "tues" => :tuesday, "tue" => :tuesday,
        "wednesday" => :wednesday, "wed" => :wednesday,
        "thursday" => :thursday, "thurs" => :thursday, "thur" => :thursday, "thu" => :thursday,
        "friday" => :friday, "fri" => :friday,
        "saturday" => :saturday, "sat" => :saturday,
        "sunday" => :sunday, "sun" => :sunday
      }.freeze
      # Monday-first order, for resolving a weekday within the current week.
      WEEKDAY_ORDER = %i[monday tuesday wednesday thursday friday saturday sunday].freeze
      # Regex alternation source, longest names first so full names win.
      WEEKDAY_ALT = WEEKDAYS.keys.sort_by { |k| -k.length }.join("|")

      # Optional trailing "[at] <time-of-day>" clause shared by the named forms.
      TOD = '(?:\s+(?:at\s+)?(.+))?'

      # in <n> <unit> [from now]
      RELATIVE = /\Ain\s+(\d+)\s*(minutes?|mins?|m|hours?|hrs?|hr|h|days?|d)(?:\s+from\s+now)?\z/
      # today [[at] <time-of-day>]    (bare → 09:00; "today at 3am", "today at 14:30")
      TODAY = /\Atoday#{TOD}\z/
      # tomorrow [[at] <time-of-day>]  (incl. "tomorrow night")
      TOMORROW = /\Atomorrow#{TOD}\z/
      # <weekday> [[at] <tod>]        → this calendar week
      WEEKDAY = /\A(#{WEEKDAY_ALT})#{TOD}\z/
      # next week [[at] <tod>]        → Monday of next week
      NEXT_WEEK = /\Anext\s+week#{TOD}\z/
      # next month [[at] <tod>]       → 1st of next month
      NEXT_MONTH = /\Anext\s+month#{TOD}\z/
      # next <weekday> [[at] <tod>]   → next calendar week
      NEXT_WEEKDAY = /\Anext\s+(#{WEEKDAY_ALT})#{TOD}\z/
      # <n> weeks from now [[at] <tod>]
      WEEKS_FROM_NOW = /\A(\d+)\s+weeks?\s+from\s+now#{TOD}\z/
      # <n> days from now [[at] <tod>]
      DAYS_FROM_NOW = /\A(\d+)\s+days?\s+from\s+now#{TOD}\z/
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
        elsif (m = TODAY.match(phrase))
          on_date(@now.to_date, m[1])
        elsif (m = TOMORROW.match(phrase))
          on_date(@now.to_date + 1, m[1])
        elsif (m = NEXT_WEEK.match(phrase))
          on_date(@now.to_date.next_week(:monday), m[1])
        elsif (m = NEXT_MONTH.match(phrase))
          on_date(@now.to_date.next_month.beginning_of_month, m[1])
        elsif (m = NEXT_WEEKDAY.match(phrase))
          weekday_time(m[1], m[2], future: true)
        elsif (m = WEEKS_FROM_NOW.match(phrase))
          on_date(@now.to_date + (m[1].to_i * 7), m[2])
        elsif (m = DAYS_FROM_NOW.match(phrase))
          on_date(@now.to_date + m[1].to_i, m[2])
        elsif (m = WEEKDAY.match(phrase))
          weekday_time(m[1], m[2], future: false)
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

      # Resolve a date + optional "[at] <tod>" clause to a local time. A nil
      # clause defaults to DEFAULT_HOUR; an unparseable clause yields nil (no match).
      def on_date(date, time_of_day)
        return at_date(date, DEFAULT_HOUR, 0) if time_of_day.nil?

        hour_minute = parse_time_of_day(time_of_day)
        hour_minute && at_date(date, hour_minute[0], hour_minute[1])
      end

      # `future: false` → that weekday in the current week (may be in the past);
      # `future: true` → that weekday in next calendar week.
      def weekday_time(name, time_of_day, future:)
        sym = WEEKDAYS.fetch(name)
        date =
          if future
            @now.to_date.next_week(sym)
          else
            @now.to_date.beginning_of_week(:monday) + WEEKDAY_ORDER.index(sym)
          end
        on_date(date, time_of_day)
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

      # "noon" | "midnight" | "2pm" | "3:10am" | "23" | "15:30" → [hour, minute] or nil.
      def parse_time_of_day(str)
        case str
        when "noon"     then [ 12, 0 ]
        when "midnight" then [ 0, 0 ]
        when "night"    then [ NIGHT_HOUR, 0 ]
        when /\A(\d{1,2}):(\d{2})\s*(am|pm)\z/ # 3:10am / 11:45pm
          twelve_hour(Regexp.last_match(1).to_i, Regexp.last_match(2).to_i, Regexp.last_match(3))
        when /\A(\d{1,2})\s*(am|pm)\z/         # 2pm / 11pm
          twelve_hour(Regexp.last_match(1).to_i, 0, Regexp.last_match(2))
        when /\A(\d{1,2}):(\d{2})\z/           # 15:30 / 23:45 (24-hour)
          hour, minute = Regexp.last_match(1).to_i, Regexp.last_match(2).to_i
          hour.between?(0, 23) && minute.between?(0, 59) ? [ hour, minute ] : nil
        when /\A(\d{1,2})\z/                   # 23 / 9 (24-hour, hour only)
          hour = Regexp.last_match(1).to_i
          hour.between?(0, 23) ? [ hour, 0 ] : nil
        end
      end

      # 12-hour clock → [hour24, minute], or nil for an invalid hour/minute.
      def twelve_hour(hour, minute, meridiem)
        return nil unless hour.between?(1, 12) && minute.between?(0, 59)

        hour %= 12
        hour += 12 if meridiem == "pm"
        [ hour, minute ]
      end

      def at_date(date, hour, minute)
        Time.zone.local(date.year, date.month, date.day, hour, minute)
      end
    end
  end
end
