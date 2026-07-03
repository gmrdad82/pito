# frozen_string_literal: true

# Handler for `show channel @handle` / `show game <id>` / `show video <id>`.
#
# Resolves a single entity by ID only (`#123` or `123`) —
# title (ILIKE) lookup is intentionally disabled (id_only_resolution!).
# Unknown reference → witty not-found via `Pito::Copy`. No reference → a usage
# hint (the no-arg picker fast-path is wired in `ChatController`).
#
# == Ordinal selectors (Phase FL)
#
# In addition to ID resolution, the handler recognises ordinal forms:
#
#   show {first|last} [<genre>] game        — all-time first/last game by release_date
#   show {first|last} [<privacy>] vid       — all-time first/last vid by published_at
#
# Ordinal is the first word after the verb. Channel scope comes from the
# shift+tab channel param (same as `list`). Genre/privacy filters are optional.
# `show last vid` is an alias for `show last published vid` (default privacy).
#
# Resolution is delegated to Pito::Chat::OrdinalResolver. Not-found (no entity
# matches the ordinal + filters + channel scope) → existing show not-found path.
#
# == Segment-driven emission (plan-0.9.5 D3)
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
        self.verb = :show
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

        # Ordinal keywords that trigger first/last resolution instead of ID lookup.
        ORDINAL_WORDS = %w[first last].freeze

        # Maps entity_kind → segment name → private emitter method symbol.
        # The table-driven loop in #emit_segments_for calls send(method_sym, entity).
        # No builder arguments live here — each private method below is the sole
        # source of truth for invocation, kind, and follow-up wiring.
        SEGMENT_EMITTERS = {
          channel: {
            "detail"      => :emit_channel_detail,
            "videos"      => :emit_channel_videos,
            "at-a-glance" => :emit_channel_at_a_glance
          }.freeze,
          vid: {
            "detail"      => :emit_vid_detail,
            "linked-game" => :emit_vid_linked_game,
            "at-a-glance" => :emit_vid_at_a_glance
          }.freeze,
          game: {
            "detail"        => :emit_game_detail,
            "similar"       => :emit_game_similar,
            "linked-videos" => :emit_game_linked_videos,
            "channels"      => :emit_game_channels,
            "at-a-glance"   => :emit_game_at_a_glance
          }.freeze
        }.freeze

        def call
          if channel_noun?
            handle_channel
          elsif video_target?(VIDEO_NOUN_FILLERS)
            handle_video
          elsif follow_up? || game_noun? || extract_ordinal
            handle_game
          else
            unknown_entity
          end
        end

        private

        # ── Channel branch (`show channel @handle`) ──────────────────────────────

        # Free-chat: a channel noun token present in the body? (show channel is a
        # chat verb; the channel @handle is resolved separately, not by id.)
        def channel_noun?
          message.body_tokens.any? { |t| CHANNEL_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        # Free-chat: an EXPLICIT game noun token present? In free chat the 2nd token
        # IS the entity (owner 2026-06-29) — a bare id (`show 123`) or unknown word
        # (`show foo`) is NEVER silently treated as a game; only `game`/`games`
        # routes here. (Follow-up replies bypass this via `follow_up?` in `call`.)
        def game_noun?
          message.body_tokens.any? { |t| GAME_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        def handle_channel
          channel = resolve_channel
          return channel_needs_ref if channel == :needs_ref
          return channel_not_found(channel_ref.presence || scoped_channel_handle) if channel.nil?

          selection = parse_selection(:channel)
          return segment_conflict_error if selection.conflict
          return segment_unknown_error(selection.unknown, :channel) if selection.unknown.any?

          emit_segments_for(channel, :channel, selection)
        end

        # Resolve the channel by @handle (case-insensitive, @-agnostic). A bare
        # `show channel` (no @handle in the body) falls back to the shift+tab
        # channel SCOPE — so it's treated as a channel, never the game picker. Only
        # truly ambiguous (no handle + @all/blank scope) → :needs_ref.
        def resolve_channel
          handle = channel_ref.presence || scoped_channel_handle
          return :needs_ref if handle.blank?

          norm = handle.to_s.sub(/\A@+/, "").downcase
          ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)
        end

        # The shift+tab channel scope as a concrete @handle, or nil for @all / blank
        # (ambiguous — a bare `show channel` then asks which channel, not which game).
        def scoped_channel_handle
          h = channel.to_s.strip
          return nil if h.blank? || %w[@all all].include?(h.downcase)

          h
        end

        # Channel-specific needs-ref (NOT the game-oriented `needs_ref`) — owner
        # 2026-06-29: a bare `show channel` must read as a channel, never a game.
        def channel_needs_ref
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.chat.show.channel_needs_ref") }
          ])
        end

        # The @handle token after stripping the verb + channel noun (and any
        # trailing segment-selection clause — see resolution_raw).
        def channel_ref
          extract_ref_from(resolution_raw, CHANNEL_NOUN_FILLERS)
        end

        # plan-0.9.5 D3: show's grammar appends selection clauses AFTER the
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

        def emit_channel_videos(channel)
          { kind: :enhanced, payload: Pito::MessageBuilder::Channel::Videos.call(channel, conversation:) }
        end

        def emit_channel_at_a_glance(channel)
          { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(channel, period: analytics_period, conversation:) }
        end

        # ── Video branch ───────────────────────────────────────────────────────

        def handle_video
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
            video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUN_FILLERS)
            return needs_ref if video == :needs_ref
            return video_not_found(target_ref(VIDEO_NOUN_FILLERS, id_key: :video_id)) if video.nil?
          end

          selection = parse_selection(:vid)
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
            game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUN_FILLERS)
            return needs_ref if game == :needs_ref
            return game_not_found(target_ref(GAME_NOUN_FILLERS, id_key: :game_id)) if game.nil?
          end

          selection = parse_selection(:game)
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

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.show.needs_ref", message_args: {})
        end

        # Free-chat with no recognised entity (bare `show`, bare id, or unknown
        # word) — no guessing (owner 2026-06-29). Render the generic "I don't get
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
          Pito::Chat::SegmentSelection.parse(message.raw, verb: :show, entity: entity_kind)
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
          Pito::Chat::Segments.for(verb: :show, entity: entity_kind).each do |seg|
            next unless selection.names.include?(seg.name)
            next if seg.emit_if && !seg.emit_if.call(entity)

            events << send(SEGMENT_EMITTERS.fetch(entity_kind).fetch(seg.name), entity)
          end
          Pito::Chat::Result::Ok.new(events:)
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
              names:  Pito::Chat::Segments.names(verb: :show, entity: entity_kind).join(", ")
            ),
            message_args: {}
          )
        end

        # ── Ordinal helpers ────────────────────────────────────────────────────

        # Returns :first or :last when the first body word after the verb is an
        # ordinal keyword, nil otherwise. Only applies to free-chat; follow-up
        # replies always use ID or list-row resolution, never ordinal selectors.
        def extract_ordinal
          return nil if follow_up?

          # Drop the verb word, inspect the first remaining token.
          rest       = message.raw.to_s.strip.sub(/\A\S+\s*/, "")
          first_word = rest.split(/\s+/).first&.downcase
          ORDINAL_WORDS.include?(first_word) ? first_word.to_sym : nil
        end

        # Extracts the genre filter for `show first|last [<genre>] game` forms.
        # Looks for a GameListFilter genre alias token in the words between the
        # ordinal and the noun filler. Returns the genre substring or nil.
        def extract_game_genre_filter
          # Drop verb + ordinal words; remove any trailing noun filler tokens.
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
          # Drop verb + ordinal words; remove any trailing noun filler tokens.
          words = message.raw.to_s.downcase.split(/\s+/).drop(2)
          words.reject! { |w| VIDEO_NOUN_FILLERS.include?(w) }
          privacy_token = words.find { |w| Pito::Chat::OrdinalResolver::VIDEO_PRIVACY_FILTERS.key?(w) }
          privacy_token ? Pito::Chat::OrdinalResolver::VIDEO_PRIVACY_FILTERS[privacy_token] : :published
        end

        # Display ref used in not-found messages for ordinal forms — the raw
        # input with the verb stripped (e.g. "last rpg game" or "first vid").
        def ordinal_ref
          message.raw.to_s.strip.sub(/\A\S+\s*/, "").strip
        end
      end
    end
  end
end
