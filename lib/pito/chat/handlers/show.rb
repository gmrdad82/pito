# frozen_string_literal: true

# Handler for `show channel @handle` / `show game <ref>` / `show video <ref>`.
#
# `ref` is a numeric id (`#123` or `123`) — resolved BYTE-IDENTICALLY to
# before — or, for game/vid, a non-numeric title, resolved through the shared
# exact-first ladder (`Game`/`Video.resolve_by_title`; see
# `Pito::TitleResolve`): exact match, then prefix, then anchored token-run
# scoring, then acronym-of-initials. `id_only_resolution!` still switches OFF
# `TargetResolution#find_by_ref`'s OWN (ILIKE) title lookup — untouched, so
# every OTHER id_only_resolution! handler (delete/reindex/platform/shinies) is
# unaffected; Show's game/vid branches resolve a title-shaped miss through the
# ladder themselves instead (`#resolve_title`). Unknown reference → witty
# not-found via `Pito::Copy`. No reference → a usage hint (the no-arg picker
# fast-path is wired in `ChatController`).
#
# == The vid's linked game, by vid ref: `show game for vid <ref>`
#
# `show game for vid <ref>` / `for video <ref>` pivots the whole request:
# `<ref>` (numeric id or title, same ladder) names a VID, and the answer is
# THAT vid's linked game — the exact emission the `game` segment tool
# (`game vid <ref>` / `linked game <ref>`) produces (`#handle_game_for_vid`).
# An unresolvable vid ref → the ordinary video not-found copy; a
# resolved-but-unlinked vid → that same segment path's SEGMENT_EMPTY_COPY
# fallback (see below).
#
# == Ordinal selectors
#
# In addition to ID resolution, the handler recognises ordinal forms:
#
#   show {first|last} [<genre>] game        — all-time first/last game by release_date
#   show {first|last} [<privacy>] vid       — all-time first/last vid by published_at
#
# Ordinal is the first word after the tool. Channel scope comes from the
# shift+tab channel param (same as `list`). Genre/privacy filters are optional.
# `show last vid` is an alias for `show last published vid` (default privacy).
#
# Resolution is delegated to Pito::Chat::OrdinalResolver. Not-found (no entity
# matches the ordinal + filters + channel scope) → existing show not-found path.
#
# == Segment-driven emission
#
# After resolving the entity the handler parses a SegmentSelection from the raw
# input (SegmentSelection.parse), then walks the Segments table in declaration
# order, emitting only the segments whose names appear in +selection.names+,
# each still guarded by its +emit_if+ lambda (skipped silently when false).
#
# Bare form → only +detail+ (the single default: true segment for all entities).
# +full+     → all segments (guards still apply).
# +with+/+only+ → per the Selection.
#
# Conflict (multiple introducers) or unknown token(s) → error Result.
module Pito
  module Chat
    module Handlers
      class Show < Pito::Chat::Handler
        self.tool = :show
        self.description_key = "pito.chat.show.descriptions.show"
        id_only_resolution!

        # `game`/`games` are noun fillers the user types but that carry no value
        # when resolving a game.
        GAME_NOUN_FILLERS  = %w[game games].freeze

        # `vid`/`vids` (canonical) and `video`/`videos` (aliases) are noun fillers
        # for the video branch.
        VIDEO_NOUN_FILLERS = %w[vid vids video videos].freeze

        # `channel`/`channels` route to the channel branch — resolved by @handle
        # (NOT a numeric id), mirroring `shinies channel @handle`.
        CHANNEL_NOUN_FILLERS = %w[channel channels].freeze

        # Union of every noun filler — used ONLY on the forced-entity path (the
        # `linked` keyed tool), where the typed noun names the
        # OTHER entity than the one resolved (`linked game #7` resolves vid #7), so
        # the ref extraction must strip whichever noun the user typed.
        ALL_NOUN_FILLERS = (CHANNEL_NOUN_FILLERS + VIDEO_NOUN_FILLERS + GAME_NOUN_FILLERS).freeze

        # Ordinal keywords that trigger first/last resolution instead of ID lookup.
        ORDINAL_WORDS = %w[first last].freeze

        # "show game for vid tekken 7" → captures "tekken 7"; "for video …" is the
        # same clause under the alternate spelling. Mirrors search.rb's
        # LIKE_CLAUSE/FOR_CLAUSE idiom — a fixed trailing clause, captured lazily
        # to end-of-string once the segment-selection clause (if any) is already
        # stripped from the text this is matched against (see #game_for_vid_ref).
        FOR_VID_CLAUSE = /\bfor\s+vid(?:eo)?\b\s+(.+?)\s*\z/i

        # Maps entity_kind → segment name → private emitter method symbol.
        # The table-driven loop in #emit_segments_for calls send(method_sym, entity).
        # No builder arguments live here — each private method below is the sole
        # source of truth for invocation, kind, and follow-up wiring.
        SEGMENT_EMITTERS = {
          channel: {
            "detail"      => :emit_channel_detail,
            "games"       => :emit_channel_games,
            "videos"      => :emit_channel_videos,
            "at-a-glance" => :emit_channel_at_a_glance
          }.freeze,
          vid: {
            "detail"      => :emit_vid_detail,
            "game"        => :emit_vid_linked_game,
            "at-a-glance" => :emit_vid_at_a_glance
          }.freeze,
          game: {
            "detail"      => :emit_game_detail,
            "similar"     => :emit_game_similar,
            "videos"      => :emit_game_linked_videos,
            "channels"    => :emit_game_channels,
            "at-a-glance" => :emit_game_at_a_glance
          }.freeze
        }.freeze

        # Maps entity_kind → segment name → copy key rendered as a lone :system
        # event when that segment is the ONLY one requested (`only <segment>` /
        # a segment tool, e.g. `games channel @h`) but its `emit_if` guard fails
        # (e.g. a channel with no linked games, or a vid with no linked game). A
        # combined view (`full`/`with …`) stays silent as before — only a SOLE
        # explicit request gets this fallback, so an empty Result (which reads
        # as broken, especially to MCP callers) never reaches the caller.
        SEGMENT_EMPTY_COPY = {
          channel: { "games" => "pito.copy.channels.games_empty" },
          vid:     { "game"  => "pito.copy.videos.linked_game_empty" }
        }.freeze

        def call
          return drive_forced_entity if @forced_entity

          for_vid_ref = game_for_vid_ref
          return handle_game_for_vid(for_vid_ref) if for_vid_ref

          if channel_noun? || channel_follow_up?
            handle_channel
          elsif video_target?(VIDEO_NOUN_FILLERS)
            handle_video
          elsif follow_up? || game_noun? || extract_ordinal
            handle_game
          else
            unknown_entity
          end
        end

        # The keyed `linked` tool FORCES the entity: `linked game
        # #7` names the linked-game segment but resolves VID #7. Route straight to
        # the forced branch, bypassing the typed-noun routing above (the typed noun
        # names the OTHER entity). Ref extraction widens to ALL_NOUN_FILLERS.
        def drive_forced_entity
          case @forced_entity
          when :vid     then handle_video
          when :game    then handle_game
          when :channel then handle_channel
          end
        end

        # Public seam for Pito::Chat::Handlers::SegmentTool. Runs
        # this tool forcing an `only <segment>` selection and returns the same
        # Result the typed `show <noun> <ref> only <segment>` form produces —
        # resolution, emission, and the not-a-segment-for-this-entity rejection all
        # flow through the unchanged branch logic. Off (@forced_segment nil) in the
        # normal typed/reply path, so byte-for-byte behaviour is preserved there.
        # +entity+ additionally FORCES the resolved entity branch,
        # for the `linked` keyed tool whose noun names the segment while the id
        # belongs to the OTHER entity. nil leaves the
        # typed-noun routing untouched, so behaviour there stays byte-identical.
        def drive_segment(segment, entity: nil)
          @forced_segment = segment
          @forced_entity  = entity
          call
        end

        # Multi-id at-a-glance: `at-a-glance videos 2,3,4` → ONE combined glance over
        # the set. Show is otherwise single-entity — ONLY the at-a-glance segment
        # supports a set (analyze/breakdowns already do multi via ScopeResolver).
        def glance_multi?
          @forced_segment == "at-a-glance" && glance_ids.size > 1
        end

        # Ids typed after the noun — `2, #4, 5` → [2, 4, 5]. Only STANDALONE numeric
        # tokens count (digits inside a word like `ps5` are never read as ids).
        def glance_ids
          message.raw.split(/[\s,]+/).filter_map { |t| Regexp.last_match(1).to_i if t.match(/\A#?(\d+)\z/) }.uniq
        end

        # Resolve the named entities and emit ONE combined pending glance; the fill
        # pipeline aggregates the metrics across the set (Scalars/MetricFill walk the
        # merged channel groups).
        def emit_multi_glance(model)
          records = model.where(id: glance_ids).to_a
          return Pito::Chat::Result::Error.new(message_key: Pito::Copy.render("pito.copy.huh"), message_args: {}) if records.empty?

          Pito::Chat::Result::Ok.new(events: [
            { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(records, period: analytics_period, conversation:) }
          ])
        end

        private

        # ── Channel branch (`show channel @handle`) ──────────────────────────────

        # Free-chat: a channel noun token present in the PRE-CLAUSE body?
        # Checks only tokens that precede any selection-clause starter (with/only/
        # without/full) so a segment name like "channels" inside a `without channels`
        # clause does not ghost-trigger the channel branch on
        # `show game … without channels`. (show channel is a chat tool; the channel
        # @handle is resolved separately, not by numeric id.)
        def channel_noun?
          message.body_tokens
                 .take_while { |t| !%w[with only without full].include?(t.value.to_s.downcase) }
                 .any? { |t| CHANNEL_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        # Free-chat: an EXPLICIT game noun token present? In free chat the 2nd token
        # IS the entity — a bare id (`show 123`) or unknown word
        # (`show foo`) is NEVER silently treated as a game; only `game`/`games`
        # routes here. (Follow-up replies bypass this via `follow_up?` in `call`.)
        # PRE-CLAUSE scoped like channel_noun?: `games`/`game` are
        # segment names too, and `show vid #3 with game` / `show channel @h with
        # games` must not ghost-trigger the game branch.
        def game_noun?
          message.body_tokens
                 .take_while { |t| !%w[with only without full].include?(t.value.to_s.downcase) }
                 .any? { |t| GAME_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        # `show game for vid <ref>` / `for video <ref>` — the captured `<ref>`
        # (or nil when the clause isn't present). Only checked when the typed
        # noun is `game` (never `vid`), so `show vid …` keeps its ordinary
        # video routing untouched even when the word "vid"/"video" happens to
        # appear elsewhere in the input. Matched against +resolution_raw+ (the
        # segment-selection clause, if any, already stripped) so `show game for
        # vid tekken 7 full` still isolates "tekken 7" as the vid ref.
        def game_for_vid_ref
          return nil unless game_noun?

          resolution_raw[FOR_VID_CLAUSE, 1]
        end

        def handle_channel
          channel = resolve_channel
          return channel_needs_ref if channel == :needs_ref
          return channel_not_found(channel_ref.presence || scoped_channel_handle) if channel.nil?

          selection = resolved_selection(:channel)
          return segment_conflict_error if selection.conflict
          return segment_unknown_error(selection.unknown, :channel) if selection.unknown.any?

          emit_segments_for(channel, :channel, selection)
        end

        # A follow-up reply sourced from a CHANNEL message (channel_detail,
        # channel_games, …) fixes the entity — a bare segment reply like
        # `#<handle> games` carries no noun, so routing must come from the
        # source's reply_target (mirrors video_target?'s follow-up arm).
        def channel_follow_up?
          follow_up? && reply_target.to_s.start_with?("channel")
        end

        # Resolve the channel by @handle (case-insensitive, @-agnostic). A bare
        # `show channel` (no @handle in the body) falls back to the shift+tab
        # channel SCOPE — so it's treated as a channel, never the game picker. Only
        # truly ambiguous (no handle + @all/blank scope) → :needs_ref.
        # In a channel-sourced follow-up with no typed handle (a bare `games` /
        # `videos` / `at-a-glance` reply), the source card's channel_id IS the
        # channel (same source-entity contract as the game/vid replies).
        def resolve_channel
          handle = channel_ref.presence || scoped_channel_handle
          if handle.blank? && channel_follow_up?
            source_id = follow_up.source_event.payload.to_h.with_indifferent_access[:channel_id]
            return ::Channel.find_by(id: source_id) if source_id.present?
          end
          return :needs_ref if handle.blank?

          # Exact @-agnostic match, then a pg_trgm fuzzy fallback.
          ::Channel.resolve_handle(handle)
        end

        # The shift+tab channel scope as a concrete @handle, or nil for @all / blank
        # (ambiguous — a bare `show channel` then asks which channel, not which game).
        def scoped_channel_handle
          h = channel.to_s.strip
          return nil if h.blank? || %w[@all all].include?(h.downcase)

          h
        end

        # Channel-specific needs-ref (NOT the game-oriented `needs_ref`) — a bare
        # `show channel` must read as a channel, never a game.
        def channel_needs_ref
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.chat.show.channel_needs_ref") }
          ])
        end

        # The @handle token after stripping the tool + channel noun (and any
        # trailing segment-selection clause — see resolution_raw).
        def channel_ref
          extract_ref_from(resolution_raw, CHANNEL_NOUN_FILLERS)
        end

        # Show's grammar appends selection clauses AFTER the
        # reference (`show game 5 full`, `show vid #3 only at-a-glance`). Strip
        # them before reference extraction so `find_by_ref` sees only the ref —
        # in free chat AND in `#<handle> show 5 full` list replies.
        def resolution_raw
          Pito::Chat::SegmentSelection.strip(super)
        end

        def resolution_rest
          Pito::Chat::SegmentSelection.strip(super)
        end

        def channel_not_found(ref)
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.channels.not_found", handle: ref) }
          ])
        end

        # ── Per-segment emitters: channel ──────────────────────────────────────

        def emit_channel_detail(channel)
          { kind: :system, payload: Pito::MessageBuilder::Channel::Detail.call(channel, conversation:) }
        end

        def emit_channel_games(channel)
          { kind: :enhanced, payload: Pito::MessageBuilder::Channel::Games.call(channel, conversation:) }
        end

        def emit_channel_videos(channel)
          { kind: :enhanced, payload: Pito::MessageBuilder::Channel::Videos.call(channel, conversation:) }
        end

        def emit_channel_at_a_glance(channel)
          { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(channel, period: analytics_period, conversation:) }
        end

        # ── Video branch ───────────────────────────────────────────────────────

        def handle_video
          return emit_multi_glance(::Video) if glance_multi?

          if (ordinal = extract_ordinal)
            # Ordinal form: `show first|last [<privacy>] vid`.
            # Delegate to OrdinalResolver; not-found → existing video_not_found path.
            video = Pito::Chat::OrdinalResolver.call(
              entity:        :video,
              ordinal:       ordinal,
              filters:       { privacy: extract_video_privacy_filter },
              channel_scope: channel
            )
            return video_not_found(ordinal_ref) if video.nil?
          else
            video = resolve_target(::Video, id_key: :video_id, noun_fillers: video_noun_fillers)
            return needs_ref if video == :needs_ref
            video ||= resolve_title(::Video, video_noun_fillers)
            if video.nil?
              ref = target_ref(video_noun_fillers, id_key: :video_id)
              return nl_soft_fail("pito.copy.videos.not_found", ref) if nl_soft_fail_ref?(ref)
              return video_not_found(ref)
            end
          end

          selection = resolved_selection(:vid)
          return segment_conflict_error if selection.conflict
          return segment_unknown_error(selection.unknown, :vid) if selection.unknown.any?

          emit_segments_for(video, :vid, selection)
        end

        # consume: false — on a `#<handle>` reply a not-found must NOT consume the
        # source list, so the owner can retry the reply without repeating it.
        def video_not_found(ref)
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end

        # ── Per-segment emitters: vid ──────────────────────────────────────────

        def emit_vid_detail(video)
          { kind: :system, payload: Pito::MessageBuilder::Video::Detail.call(video, conversation:) }
        end

        def emit_vid_linked_game(video)
          { kind: :enhanced, payload: Pito::MessageBuilder::Video::LinkedGame.call(video, conversation:) }
        end

        def emit_vid_at_a_glance(video)
          { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(video, period: analytics_period, conversation:) }
        end

        # ── Game branch ────────────────────────────────────────────────────────

        def handle_game
          return emit_multi_glance(::Game) if glance_multi?

          if (ordinal = extract_ordinal)
            # Ordinal form: `show first|last [<genre>] game`.
            # Delegate to OrdinalResolver; not-found → existing game_not_found path.
            game = Pito::Chat::OrdinalResolver.call(
              entity:        :game,
              ordinal:       ordinal,
              filters:       { genre: extract_game_genre_filter },
              channel_scope: channel
            )
            return game_not_found(ordinal_ref) if game.nil?
          else
            game = resolve_target(::Game, id_key: :game_id, noun_fillers: game_noun_fillers)
            return needs_ref if game == :needs_ref
            game ||= resolve_title(::Game, game_noun_fillers)
            if game.nil?
              ref = target_ref(game_noun_fillers, id_key: :game_id)
              return nl_soft_fail("pito.copy.games.not_found", ref) if nl_soft_fail_ref?(ref)
              return game_not_found(ref)
            end
          end

          selection = resolved_selection(:game)
          return segment_conflict_error if selection.conflict
          return segment_unknown_error(selection.unknown, :game) if selection.unknown.any?

          emit_segments_for(game, :game, selection)
        end

        # consume: false — see video_not_found: a not-found reply stays repliable.
        def game_not_found(ref)
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        # ── Game-for-vid pivot (`show game for vid <ref>`) ─────────────────────

        # Resolves the named VID (id or title), then answers with ITS linked
        # game — a solo `only game` selection on the VID entity, driven through
        # the exact same #emit_segments_for the `game` segment tool's
        # forced-entity route (`drive_segment("game", entity: :vid)`) ends up
        # calling. Byte-identical outcome to `game vid <the vid's id>` for the
        # same vid: unresolvable ref → the ordinary video not-found copy;
        # resolved-but-unlinked → that segment's existing (silent) outcome —
        # never new copy.
        def handle_game_for_vid(vid_ref)
          video = resolve_id_or_title(::Video, vid_ref)
          return video_not_found(vid_ref) if video.nil?

          selection = Pito::Chat::SegmentSelection.only(tool: :show, entity: :vid, segment: "game")
          emit_segments_for(video, :vid, selection)
        end

        # ── Per-segment emitters: game ─────────────────────────────────────────

        def emit_game_detail(game)
          { kind: :system, payload: Pito::MessageBuilder::Game::Detail.call(game, conversation:) }
        end

        def emit_game_similar(game)
          { kind: :enhanced, payload: Pito::MessageBuilder::Game::SimilarGames.call(game, conversation:) }
        end

        def emit_game_linked_videos(game)
          { kind: :enhanced, payload: Pito::MessageBuilder::Game::LinkedVideos.call(game, conversation:) }
        end

        def emit_game_channels(game)
          { kind: :enhanced, payload: Pito::MessageBuilder::Game::Channels.pending(game, conversation:) }
        end

        def emit_game_at_a_glance(game)
          { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(game, period: analytics_period, conversation:) }
        end

        # ── Shared helpers ─────────────────────────────────────────────────────

        # Returns the explicit period param when present; falls back to the
        # conversation's persisted stats_period so nil never reaches the analytics layer.
        def analytics_period = period.presence || conversation.stats_period

        # Noun fillers stripped during ref extraction. On the forced-entity path
        # (the `linked` keyed tool) the typed noun names the OTHER entity, so widen
        # to ALL_NOUN_FILLERS; otherwise the branch's own fillers (byte-identical).
        def video_noun_fillers = @forced_entity ? ALL_NOUN_FILLERS : VIDEO_NOUN_FILLERS
        def game_noun_fillers  = @forced_entity ? ALL_NOUN_FILLERS : GAME_NOUN_FILLERS

        # Non-numeric-ref fallback for the free-chat game/vid branches: when
        # +resolve_target+ came back nil (id_only_resolution! keeps its OWN ILIKE
        # lookup off), re-extract the SAME ref and resolve it through the shared
        # title ladder instead. Follow-up replies stay id-based only — this never
        # runs there, so detail/list-reply resolution is untouched.
        def resolve_title(model_class, noun_fillers)
          return nil if follow_up?

          ref = extract_ref_from(resolution_raw, noun_fillers)
          resolve_id_or_title(model_class, ref) if ref.present?
        end

        # ID-form (`#7`/`7`) resolves by id; any other ref resolves through the
        # shared exact-first title ladder (`Game`/`Video.resolve_by_title`) —
        # mirrors TargetResolution#find_by_ref's id-detection idiom, but (unlike
        # that shared helper, which id_only_resolution! switches off for every
        # other handler) always tries the ladder for a non-numeric ref. Used both
        # by #resolve_title above and by the game-for-vid pivot, which has no
        # prior id attempt of its own to fall back from.
        def resolve_id_or_title(model_class, ref)
          id = ref.to_s.sub(/\A#\s*/, "")
          return model_class.find_by(id: id) if id.match?(/\A\d+\z/)

          model_class.resolve_by_title(ref)
        end

        # NL soft-fail (3.0.1 P7): a free-chat NON-NUMERIC ref that missed the
        # title ladder looks like free text the parser's first-token match
        # captured ("show me my tekken vids") — emit the nl_fallback marker so
        # Pito::Dispatch::Router re-runs the ORIGINAL utterance through the NL
        # gate. Numeric refs ("show game 99999" — a genuinely missing id),
        # follow-up replies (machine-reconstructed input, never free text), and
        # nl_eligible: false dispatches (a RECONSTRUCTED follow-up re-dispatch
        # with no FollowUpContext — e.g. Pito::FollowUp::Handlers::GameSimilar's
        # `show game <ref>`, which deliberately omits follow_up so the title
        # ladder still runs — see Pito::Dispatch::Router's class header) keep
        # the crisp not-found unchanged.
        def nl_soft_fail_ref?(ref)
          !follow_up? && nl_eligible? && ref.present? && !ref.to_s.sub(/\A#\s*/, "").match?(/\A\d+\z/)
        end

        # The marker still carries the crisp not-found copy: a consumer that
        # renders it un-fallen-back (the nl_retry loop guard, MCP projection)
        # degrades to exactly the message this branch used to emit.
        def nl_soft_fail(key, ref)
          Pito::Chat::Result::Error.new(message_key: key, message_args: { ref: ref }, nl_fallback: true)
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.show.needs_ref", message_args: {})
        end

        # Free-chat with no recognised entity (bare `show`, bare id, or unknown
        # word) — no guessing. Render the generic "I don't get
        # it" dictionary (`pito.copy.huh`, reused per owner). Pre-rendered so the
        # finalizer routes it to `text:` while keeping the :error chrome.
        def unknown_entity
          Pito::Chat::Result::Error.new(message_key: Pito::Copy.render("pito.copy.huh"), message_args: {})
        end

        # ── Segment-selection helpers ──────────────────────────────────────────

        # Parses the trailing selection clause from the raw input for the given entity.
        # @param entity_kind [Symbol] :channel, :vid, or :game
        # @return [Pito::Chat::SegmentSelection::Selection]
        def parse_selection(entity_kind)
          Pito::Chat::SegmentSelection.parse(message.raw, tool: :show, entity: entity_kind)
        end

        # The selection to emit. Normally the trailing-clause parse. When a segment
        # tool forced a single segment (drive_segment), returns the SAME Selection
        # that `only <segment>` would parse to for this entity — validated against
        # the entity's table so an off-entity segment (e.g. `similar` on a channel)
        # lands in `unknown` and yields the identical `segments.unknown` rejection.
        # @param entity_kind [Symbol] :channel, :vid, or :game
        # @return [Pito::Chat::SegmentSelection::Selection]
        def resolved_selection(entity_kind)
          return parse_selection(entity_kind) unless @forced_segment

          Pito::Chat::SegmentSelection.only(tool: :show, entity: entity_kind, segment: @forced_segment)
        end

        # Walks the segment table in declaration order, emitting only the segments
        # whose names appear in +selection.names+, each guarded by its +emit_if+
        # (skipped silently when the guard returns false).
        #
        # @param entity      [Object]  the resolved entity record
        # @param entity_kind [Symbol]  :channel, :vid, or :game
        # @param selection   [Pito::Chat::SegmentSelection::Selection]
        # @return [Pito::Chat::Result::Ok]
        def emit_segments_for(entity, entity_kind, selection)
          events = []
          Pito::Chat::Segments.for(tool: :show, entity: entity_kind).each do |seg|
            next unless selection.names.include?(seg.name)

            if seg.emit_if && !seg.emit_if.call(entity)
              empty_event = solo_empty_event(entity_kind, seg.name, selection)
              events << empty_event if empty_event
              next
            end

            events << send(SEGMENT_EMITTERS.fetch(entity_kind).fetch(seg.name), entity)
          end

          # Append segments footer to the first emitted message.
          if events.any?
            all_names = Pito::Chat::Segments.names(tool: :show, entity: entity_kind)
            addable   = all_names - selection.names
            removable = selection.names & all_names
            footer    = Pito::Lists::OptionsFooter.call(
              addable:   addable,
              removable: removable,
              sort_keys: [],
              noun:      "segments"
            )
            events.first[:payload]["list_footer"] = footer if footer
          end

          Pito::Chat::Result::Ok.new(events:)
        end

        # A friendly :system fallback for a segment whose `emit_if` guard failed
        # AND that was the SOLE segment requested (`only <segment>` / a segment
        # tool) — nil when the request was combined (`full`/`with …`, where the
        # existing silent-skip stays) or when no fallback copy is declared for
        # this entity_kind/segment pair.
        def solo_empty_event(entity_kind, segment_name, selection)
          return nil unless selection.names == [ segment_name ]

          key = SEGMENT_EMPTY_COPY.dig(entity_kind, segment_name)
          return nil unless key

          { kind: :system, payload: Pito::MessageBuilder::Text.call(key) }
        end

        def segment_conflict_error
          Pito::Chat::Result::Error.new(
            message_key: Pito::Copy.render("pito.copy.segments.conflict"),
            message_args: {}
          )
        end

        def segment_unknown_error(unknowns, entity_kind)
          Pito::Chat::Result::Error.new(
            message_key: Pito::Copy.render(
              "pito.copy.segments.unknown",
              tokens: unknowns.join(", "),
              names:  Pito::Chat::Segments.names(tool: :show, entity: entity_kind).join(", ")
            ),
            message_args: {}
          )
        end

        # ── Ordinal helpers ────────────────────────────────────────────────────

        # Returns :first or :last when the first body word after the tool is an
        # ordinal keyword, nil otherwise. Only applies to free-chat; follow-up
        # replies always use ID or list-row resolution, never ordinal selectors.
        def extract_ordinal
          return nil if follow_up?

          # Drop the tool word, inspect the first remaining token.
          rest       = message.raw.to_s.strip.sub(/\A\S+\s*/, "")
          first_word = rest.split(/\s+/).first&.downcase
          ORDINAL_WORDS.include?(first_word) ? first_word.to_sym : nil
        end

        # Extracts the genre filter for `show first|last [<genre>] game` forms.
        # Looks for a GameListFilter genre alias token in the words between the
        # ordinal and the noun filler. Returns the genre substring or nil.
        def extract_game_genre_filter
          # Drop tool + ordinal words; remove any trailing noun filler tokens.
          words = message.raw.to_s.downcase.split(/\s+/).drop(2)
          words.reject! { |w| GAME_NOUN_FILLERS.include?(w) }
          genre_token = words.find { |w| Pito::Chat::GameListFilter::GENRE_ALIASES.key?(w) }
          genre_token ? Pito::Chat::GameListFilter::GENRE_ALIASES[genre_token] : nil
        end

        # Extracts the privacy filter for `show first|last [<privacy>] vid` forms.
        # Returns the scope Symbol for OrdinalResolver, or :published when no
        # privacy word is present — fulfilling the alias rule
        # `show last vid` = `show last published vid`.
        def extract_video_privacy_filter
          # Drop tool + ordinal words; remove any trailing noun filler tokens.
          words = message.raw.to_s.downcase.split(/\s+/).drop(2)
          words.reject! { |w| VIDEO_NOUN_FILLERS.include?(w) }
          privacy_token = words.find { |w| Pito::Chat::OrdinalResolver::VIDEO_PRIVACY_FILTERS.key?(w) }
          privacy_token ? Pito::Chat::OrdinalResolver::VIDEO_PRIVACY_FILTERS[privacy_token] : :published
        end

        # Display ref used in not-found messages for ordinal forms — the raw
        # input with the tool stripped (e.g. "last rpg game" or "first vid").
        def ordinal_ref
          message.raw.to_s.strip.sub(/\A\S+\s*/, "").strip
        end
      end
    end
  end
end
