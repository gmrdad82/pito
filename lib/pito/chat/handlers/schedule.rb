# frozen_string_literal: true

# Handler for the `schedule video <id> <when>` chat tool.
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
        self.tool = :schedule
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

          # `schedule <id> slate [only @h1, @h2]` (or a reply `#<h> schedule slate`) →
          # the upcoming-schedule planning view rather than the schedule-a-time flow.
          # `slate` may be followed by an `only @handles` channel filter, so match it
          # anywhere (not just as the last token).
          slate_idx = body.index { |t| t.value.to_s.downcase == SLATE_KEYWORD }
          return slate(body, slate_idx) if slate_idx

          # `schedule <id> <when>, <id> <when>, …` — the mass form (WP3). A comma
          # ANYWHERE in the (noun-filler-stripped) body means mass; the slate
          # branch above already returned for `slate only @h1, @h2`, so by the
          # time we get here a comma can only mean the mass grammar. No comma →
          # the single path below runs byte-identical to pre-WP3.
          return mass(body) if body.any? { |t| t.type == :comma }

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

          # YouTube's own publishAt constraint: private + NEVER-published only
          # (Video#already_published?). Check this before the time gates below
          # — it's unconditional, so failing fast here beats parsing the rest
          # of the flow just to hit it again at confirm time.
          if video.already_published?
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system,
                payload: Pito::MessageBuilder::Text.call("pito.copy.videos.schedule_already_public", title: video.title) }
            ])
          end

          if publish_time <= Time.current
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system,
                payload: Pito::MessageBuilder::Text.call("pito.copy.videos.schedule_in_past", title: video.title) }
            ])
          end

          if publish_time < 30.minutes.from_now
            return Pito::Chat::Result::Error.new(message_key: "pito.chat.schedule.too_soon", message_args: {})
          end

          # Stage-time dry-run: does this <when> collide with another scheduled
          # video on the same channel within the 60-min spacing window
          # (Video#publish_spacing_within_channel, on: :schedule)? Surfacing the
          # conflict here — before the confirmation prompt even renders — beats
          # making the user confirm only to hit the same rejection at the
          # executor. assign_attributes is a plain in-memory mutation (no save);
          # restore_attributes undoes it either way so the video handed to
          # ScheduleConfirmation.call below (and any caller reusing `video`) is
          # never left carrying the dry-run's staged attributes.
          video.assign_attributes(privacy_status: :private, publish_at: publish_time)
          conflict = !video.valid?(:schedule)
          collision = video.publish_spacing_collision if conflict
          video.restore_attributes

          if conflict
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system,
                payload: Pito::MessageBuilder::Text.call("pito.copy.videos.schedule_conflict",
                  title: video.title,
                  other: collision&.title.to_s,
                  when: Pito::Formatter::SyncStamp.call(collision&.publish_at)) }
            ])
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
        def slate(body, slate_idx)
          events = Pito::MessageBuilder::Video::Slate.call(
            exclude_id:    slate_exclude_id(body[0...slate_idx]),
            channel_scope: channel.presence || conversation.scope_channel,
            only_handles:  slate_only_handles,
            period:        conversation.stats_period,
            conversation:  conversation
          )
          Pito::Chat::Result::Ok.new(events: events)
        end

        # `slate only @h1, @h2` → the explicit channel filter (union). Handles come
        # from the raw so comma / `@` tokenisation never matters; empty when no `only`.
        def slate_only_handles
          return [] unless message.raw.match?(/\bonly\b/i)

          message.raw.scan(/@[A-Za-z0-9_.\-]+/)
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

        # ── Mass form (WP3): `schedule <id> <when>, <id> <when>, …` ────────────────
        #
        # All-or-nothing behind ONE confirmation: every comma-separated segment must
        # clear a 6-stage ladder before a single :confirmation event is built. The
        # FIRST stage a segment (or the batch) fails aborts the WHOLE thing — never
        # a partial confirmation — naming the offending segment/id/pair. Every
        # failure mode folds into just four copy keys (bad_segment / duplicate /
        # already_public / conflict): there's exactly one outcome here — abort,
        # name the offender — regardless of WHY. The executor re-runs the real
        # validation at confirm time
        # (Pito::Confirmation::Executor#confirm_video_schedule_mass); this is
        # a stage-time dry-run, same spirit as the single path's own.
        #
        #   1. parse       — TimeParser finds a <when>, AND the ref is a single
        #                    #?\d+ id. Mass has no title-ref resolution — same as
        #                    the single path (resolve_video already requires a
        #                    numeric ref; a title ref there is a not_found, never
        #                    a lookup) — so a non-numeric ref is rejected right here.
        #   2. dedupe      — no id may repeat across segments.
        #   3. resolve     — every id must resolve to a real ::Video.
        #   4. eligibility — no vid may already be public on YouTube (YouTube's
        #                    own status.publishAt constraint: private + never-
        #                    published only — see Video#already_published?).
        #   5. timing      — every <when> must be future AND ≥30 minutes out.
        #   6. spacing     — sorted by publish_at ascending: a DB dry-run
        #                    (assign_attributes + valid?(:schedule), same as the
        #                    single path) catches a collision against already-
        #                    scheduled rows, PLUS an in-memory pairwise check against
        #                    EARLIER batch items on the SAME channel — nothing is
        #                    persisted yet, so the DB dry-run alone can't see its own
        #                    batch-mates.
        def mass(body)
          parsed = []
          split_on_commas(body).each do |tokens|
            status, info = parse_mass_segment(tokens)
            return mass_abort("pito.copy.videos.mass_schedule_bad_segment", **info) if status == :bad

            parsed << info
          end

          if (dup_id = duplicate_id(parsed))
            return mass_abort("pito.copy.videos.mass_schedule_duplicate", id: dup_id)
          end

          videos = ::Video.where(id: parsed.map { |p| p[:id] }.uniq).index_by { |v| v.id.to_s }
          parsed.each do |p|
            next if videos[p[:id]]

            return mass_abort("pito.copy.videos.mass_schedule_bad_segment",
                               segment: p[:segment], reason: "no vid ##{p[:id]} in your library")
          end

          items = parsed.map { |p| { video: videos[p[:id]], publish_at: p[:time], segment: p[:segment] } }

          items.each do |item|
            if item[:video].already_published?
              return mass_abort("pito.copy.videos.mass_schedule_already_public", title: item[:video].title)
            end

            if item[:publish_at] <= Time.current
              return mass_abort("pito.copy.videos.mass_schedule_bad_segment",
                                 segment: item[:segment], reason: "that time is already in the past")
            end

            if item[:publish_at] < 30.minutes.from_now
              return mass_abort("pito.copy.videos.mass_schedule_bad_segment",
                                 segment: item[:segment], reason: "that's under 30 minutes away")
            end
          end

          sorted = items.sort_by { |item| item[:publish_at] }
          sorted.each_with_index do |item, idx|
            video = item[:video]
            video.assign_attributes(privacy_status: :private, publish_at: item[:publish_at])
            conflict  = !video.valid?(:schedule)
            collision = video.publish_spacing_collision if conflict
            video.restore_attributes

            if conflict
              return mass_abort("pito.copy.videos.mass_schedule_conflict",
                                 title: video.title, other: collision&.title.to_s,
                                 when: Pito::Formatter::SyncStamp.call(collision&.publish_at))
            end

            earlier = sorted[0...idx].find do |e|
              e[:video].channel_id == video.channel_id &&
                (item[:publish_at] - e[:publish_at]).abs < ::Video::SCHEDULE_SPACING
            end
            next unless earlier

            return mass_abort("pito.copy.videos.mass_schedule_conflict",
                               title: video.title, other: earlier[:video].title,
                               when: Pito::Formatter::SyncStamp.call(earlier[:publish_at]))
          end

          Pito::Chat::Result::Ok.new(events: [
            { kind: :confirmation,
              payload: Pito::MessageBuilder::Video::MassScheduleConfirmation.call(sorted, conversation: conversation) }
          ])
        end

        # Split +tokens+ on :comma boundaries (commas themselves dropped). A
        # leading/trailing/doubled comma yields an empty segment, which
        # parse_mass_segment rejects at stage 1 (TimeParser sees no tokens to work
        # with).
        def split_on_commas(tokens)
          segments = [ [] ]
          tokens.each do |t|
            t.type == :comma ? segments.push([]) : segments.last.push(t)
          end
          segments
        end

        # Stage 1 for ONE segment: TimeParser finds the <when> (same split-search
        # algorithm the single path uses via extract_when), and the leading ref
        # must be a single #?\d+ id.
        # Returns [:ok, { id:, time:, segment: }] or [:bad, { segment:, reason: }]
        # — the :bad hash's keys double as the mass_schedule_bad_segment copy args.
        def parse_mass_segment(tokens)
          text   = segment_text(tokens)
          result = Pito::Schedule::TimeParser.call(tokens)
          if result.nil?
            return [ :bad, { segment: text.presence || "(blank)",
                              reason:  "couldn't find a video id and a time there" } ]
          end

          ref = result.ref_tokens.map(&:value).join(" ").strip.sub(/\A#\s*/, "")
          unless ref.match?(/\A\d+\z/)
            return [ :bad, { segment: text, reason: "needs a single numeric id, not a title" } ]
          end

          [ :ok, { id: ref, time: result.time, segment: text } ]
        end

        # Reconstructs a token chunk back into readable text for error copy —
        # mirrors Pito::Schedule::TimeParser's own #reconstruct (private there).
        def segment_text(tokens)
          tokens.each_with_index.map { |t, i| (i.positive? && t.preceded_by_space ? " " : "") + t.value.to_s }.join.strip
        end

        # The first id that appears more than once across parsed segments, or nil.
        def duplicate_id(parsed)
          ids = parsed.map { |p| p[:id] }
          ids.find { |id| ids.count(id) > 1 }
        end

        def mass_abort(key, **args)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(key, **args) }
          ])
        end
      end
    end
  end
end
