# frozen_string_literal: true

# Handler for the `list` chat tool — games, channels, and videos.
#
# Dispatches based on the noun in the raw input:
#   `list` / `list games`   → game library (title-sorted, filterable, follow-up-able)
#   `list channels`         → connected channel cards
#   `list videos [filter]`  → video list, scoped by channel filter + optional privacy
#
# ## Video listing
#
# Syntax: `list videos [published|unlisted|scheduled|private|draft]`
#
# Channel scope comes from `self.channel` (the param threaded through the
# dispatcher, e.g. "@all" or "@handle"):
#   "@all" (or nil/blank) → all channels.
#   "@<handle>"           → videos for that channel only; unknown handle → error.
#
# Visibility filter (composes with `with` columns):
#   "published" → Video.published (public)
#   "unlisted"  → Video.unlisted
#   "scheduled" → Video.scheduled (future publish_at)
#   "private"   → Video.private_unscheduled (private AND NOT scheduled — D2)
#   "draft"     → same as "private" (YouTube Studio's own word for it)
#   (none)      → all videos regardless of privacy_status
#
# Ordering: id DESC by default (biggest/newest first); sort clauses override.
#
# Follow-up: video list IS stamped as `reply_target: "video_list"`, enabling
# follow-up reply tools (show, delete, link, unlink, with, without, sort/order).
#
# NOTE: `game`/`games`/`gamez` all resolve to the games noun, so `list` and
# `list games` parse identically — both land here. Noun routing (channels / vids
# / games) is driven by the shared Grammar::Vocabularies::NOUNS registry, so the
# singular aliases (`channel`, `video`, `vid`) route just like their plurals.
#
# Filtering syntax for games: `list games [upcoming] [<genres>…] [<platforms>…]`
# All parts optional, order-independent. See Pito::Chat::GameListFilter.
module Pito
  module Chat
    module Handlers
      class List < Pito::Chat::Handler
        self.tool = :list
        self.description_key = "pito.chat.list.descriptions.list"

        VISIBILITY_FILTERS = {
          "published" => :published,
          "unlisted"  => :unlisted,
          "scheduled" => :scheduled,
          "private"   => :private_unscheduled,
          # `draft` is a token ALIAS for the same scope as `private` (3.0.1
          # P11/P36) — YouTube Studio's own UI calls an unpublished,
          # not-yet-scheduled upload a "draft"; mirrors the tools.yml
          # `filters.vids.private.tokens: [private, draft]` declaration.
          "draft"     => :private_unscheduled
        }.freeze

        # Width-aware column auto-fill. With no `with` clause, `list` fills
        # canonical-order columns to a budget derived from the scrollback width
        # (`viewport_width`, px) so the table isn't sparse — more columns on a
        # wider viewport. COLUMN_BASE_PX is the room the fixed id+title columns
        # want; COLUMN_PER_PX is one added column's rough share of the rest.
        #
        # MAX_AUTOFILL_COLS caps the count at what the `.pito-data-grid` CSS can
        # render: it defines templates only up to data-cols="8" (id + title +
        # SIX added). Going past that drops to the 2-column fallback and the grid
        # visibly busts — so auto-fill never exceeds six added columns.
        MAX_AUTOFILL_COLS = 6
        COLUMN_BASE_PX    = 360
        COLUMN_PER_PX     = 200

        # ── Shared query builders ────────────────────────────────────────────
        # Class-level so the `next` follow-up handlers (FollowUp::Handlers::
        # VideoList/GameList/ChannelList) can replay the EXACT first-page query
        # from a persisted cursor — one source of truth for scoping /
        # eager-loading / ordering, so page N+1 can never drift from page 1.

        # Resolve a channel by handle (stored with or without leading "@").
        def self.find_channel_by_handle(handle)
          norm = handle.to_s.sub(/\A@+/, "")
          ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)
        end

        # Distinct channel @handles across the FULL (un-paginated) video scope —
        # the single source of truth for BOTH the intro's channel reference and
        # the single-channel column-suppression decision (they can never
        # disagree, and neither is ever re-derived per page — see
        # #video_channel_context, the only caller). A channel-scoped list
        # already knows its one channel and skips the query entirely
        # (`known_channel` — "single-channel by definition").
        #
        # @param scope         [ActiveRecord::Relation] the un-paginated video scope
        # @param known_channel [::Channel, nil]
        # @return [Array<String>] @handles, alphabetical, deduplicated
        def self.channel_handles_for_videos(scope, known_channel: nil)
          return [ known_channel.at_handle ] if known_channel

          channel_ids = scope.distinct.pluck(:channel_id)
          return [] if channel_ids.empty?

          by_id = ::Channel.where(id: channel_ids).index_by(&:id)
          channel_ids.filter_map { |id| by_id[id]&.at_handle }.sort_by(&:downcase)
        end

        # Same contract as .channel_handles_for_videos, but for games — a game
        # carries no channel of its own (Recommendations Design B: a channel is
        # its videos), so this reaches channels through the games' linked vids.
        #
        # @param game_ids      [Array<Integer>] the full result set's game ids
        # @param known_channel [::Channel, nil]
        # @return [Array<String>] @handles, alphabetical, deduplicated
        def self.channel_handles_for_games(game_ids, known_channel: nil)
          return [ known_channel.at_handle ] if known_channel
          return [] if game_ids.empty?

          channel_ids = ::Video.joins(:video_game_links)
                                .where(video_game_links: { game_id: game_ids })
                                .distinct
                                .pluck(:channel_id)
          return [] if channel_ids.empty?

          by_id = ::Channel.where(id: channel_ids).index_by(&:id)
          channel_ids.filter_map { |id| by_id[id]&.at_handle }.sort_by(&:downcase)
        end

        # The videos list relation: eager-loads per the selected columns and
        # orders id DESC (biggest/newest first; sort clauses override later).
        def self.videos_relation(base, columns:)
          includes_args = [ :channel ]
          if columns.any?
            includes_args << :linked_games
            includes_args << :stats
          end
          base.includes(*includes_args).order(id: :desc)
        end

        # The games list relation: eager-loads per the selected columns
        # (no-op when no columns are selected — id+title needs no associations).
        def self.games_relation(games, columns:)
          return games if columns.empty?

          includes_args = [ :genres, :developer_companies, :publisher_companies ]
          includes_args << { linked_videos: :channel } if columns.include?(:channels)
          games.includes(*includes_args)
        end

        # Scope games to those with ≥1 linked video on the given channel.
        def self.games_scoped_to_channel(games, channel)
          games.joins(video_game_links: :video).where(videos: { channel_id: channel.id }).distinct
        end

        # The channels list relation: connected channels only (a connection-less
        # orphan row is never a real channel), ordered by latest upload activity.
        def self.channels_relation
          ::Channel.where.not(youtube_connection_id: nil)
                   .includes(:youtube_connection)
                   .order(
                     Arel.sql(
                       "(SELECT MAX(videos.published_at) FROM videos WHERE videos.channel_id = channels.id) DESC NULLS LAST, channels.id DESC"
                     )
                   )
        end

        def call
          # The noun (channels/videos/games) is whatever precedes the first clause
          # keyword. A `with <columns>` clause may legitimately contain "channels"
          # (the games Channels column) or "video", which must NOT be mistaken for
          # the noun — otherwise `list games with channels` routes to `list channels`.
          head = noun_head(message.raw)
          # Noun routing is driven by the centralized :nouns registry (shared with
          # the typeahead), so `channels`/`vids`/`games` and every alias —
          # `channel`, `video(s)`, `vid`, `game`, `gamez` — resolve in one place.
          # resolve_fuzzy adds typo-tolerance: near-misses within edit-distance
          # threshold are corrected and a brief note event is prepended.
          noun, noun_correction = detected_noun(head)
          result = case noun
          when "channels" then list_channels
          when "vids"     then list_videos
          else                 list_games(head)
          end
          prepend_typo_note(result, noun_correction)
        end

        private

        # Explicit ids typed after the noun — `list videos 2, #4, #5, 7` → [2, 4, 5, 7]
        # (comma and/or space separated, optional `#`). When present, the list is
        # EXACTLY those entities: channel scope + visibility filter are bypassed (you
        # named the rows). Only STANDALONE numeric tokens count — digits inside a word
        # (`ps5`, `2077`-as-a-genre) never read as ids. Order is the typed order.
        def explicit_ids
          message.raw.split(/[\s,]+/).filter_map { |t| Regexp.last_match(1).to_i if t.match(/\A#?(\d+)\z/) }.uniq
        end

        # Order a relation/array by the typed id order and render as a list payload
        # via the given builder, preserving the id sequence the user asked for.
        def id_ordered(records, ids)
          by_id = records.index_by(&:id)
          ids.filter_map { |id| by_id[id] }
        end

        # Returns the part of the raw input that precedes the first clause keyword
        # (`with`, or a sort verb: sort/sorted/order/ordered). The noun is detected
        # from this head so that column names inside a clause (e.g. the games
        # `channels` column) never get read as the `list channels` / `list videos`
        # noun.
        def noun_head(raw)
          raw.to_s.split(/\b(?:with|sort(?:ed)?|order(?:ed)?)\b/i, 2).first.to_s
        end

        # Games path: handles `list [games] [filters…]`.
        # Extracted from `call` so that the typo-correction note can be prepended
        # uniformly across all noun branches (channels / vids / games).
        #
        # Allowlist over denylist: arbitrary filler is dropped silently. The
        # only non-list path is a typo that is fuzzy-close to a real
        # genre/platform/noun term → offer a "did you mean" correction instead
        # of listing. Checked against the head only, so `with <columns>` /
        # `sorted by` clauses never trip it.
        def list_games(head)
          ids = explicit_ids
          return games_by_ids_result(ids) if ids.any?

          return games_list_help if message.raw.match?(/(?:\A|\s)--help(?:\s|\z)/)

          game_suggestions = Pito::Chat::GameListFilter.suggestions(head)
          return did_you_mean(game_suggestions) if game_suggestions.any?

          # No-guess: a head token that is neither the tool, an
          # entity noun, nor a recognised game filter (genre / platform / `upcoming`)
          # is genuinely unknown. Near-miss typos were already caught by
          # `suggestions`/did_you_mean above, so anything left is gibberish → the
          # generic `pito.copy.huh` error instead of silently listing ALL games.
          # Bare `list` and valid filters (`list rpg`, `list upcoming`) are unaffected.
          return unknown_entity if unrecognized_head_token?(head)

          # F-2 (live 2026-07-18): a `with <col>` clause whose token(s) don't
          # map to a known Game column reads as a FILTER attempt that slipped
          # past the head check ("list games with hard bosses" — the owner
          # wanted a difficulty search, not a "hard bosses" column).
          # WithColumns.parse silently drops what it can't map (by design —
          # see its own header); this is the guard that stops that silence
          # from turning into an unfiltered full list. Fires only when a
          # `with` clause is present AND at least one of its tokens is
          # unrecognized — a clause of all-recognized columns (`with genre`)
          # is unaffected.
          return unknown_entity if unrecognized_with_filter?(message.raw, vocabulary: Pito::MessageBuilder::Game::ListColumns.vocabulary)

          filtered = Pito::Chat::GameListFilter.filtered?(message.raw)
          games    = Pito::Chat::GameListFilter.call(message.raw)

          # Upcoming games are unreleased → no game↔vid links, so the channel
          # scope (which requires a link) would always exclude them. Show all
          # upcoming regardless of the shift+tab channel.
          upcoming = Pito::Chat::GameListFilter.upcoming?(message.raw)
          if upcoming
            channel_scoped = false
          else
            games, error = scope_games_to_channel(games)
            return error if error

            channel_scoped = resolved_channel_handle.present?
          end

          # Single-channel suppression + intro reference — decided ONCE from the
          # FULL un-paginated set, never per-page (see #game_channel_context).
          # Skipped for `upcoming` (unreleased games carry no channel link at
          # all — nothing to enumerate or suppress).
          set_channels, suppressed_columns =
            upcoming ? [ [], [] ] : game_channel_context(games, known_channel: channel_scoped ? channel_scope_object : nil)

          # Parse extra columns; excluding suppressed ones from the auto-fill
          # candidate pool lets the width budget promote the next canonical
          # column instead of coming up short. An explicit `with channel` is
          # stripped just the same right after (post-hoc — no "budget" to
          # protect there).
          columns = Pito::Chat::WithColumns.parse(
            message.raw,
            vocabulary: Pito::MessageBuilder::Game::ListColumns.vocabulary
          )
          columns = auto_filled_columns(Pito::MessageBuilder::Game::ListColumns, exclude: suppressed_columns) if columns.empty?
          columns -= suppressed_columns

          games = self.class.games_relation(games, columns:)

          if games.empty?
            return (filtered || channel_scoped) ? games_filter_empty : games_empty
          end

          # `list games upcoming` renders as a horizon-split PAIR (like analyze):
          # a :system card of games releasing within 30 days, and an :enhanced card
          # of the later/TBA ones (ironic — they may never actually release).
          return list_games_upcoming(games, columns:) if upcoming

          sort = Pito::Chat::SortClause.parse(message.raw)
          if sort
            key = Pito::MessageBuilder::Game::ListColumns.sort_key_for(
              sort[:token], selected_columns: columns
            )
            if key.nil?
              payload = Pito::MessageBuilder::Text.call(
                "pito.copy.list.sort_column_not_visible",
                column: sort[:token]
              )
              return Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
            end
            games = games.to_a.sort_by { |g| key.call(g) }
            games.reverse! if sort[:direction] == :desc
          end

          page = page_size
          # Sorted path already materialized (in-memory sort) — size is free.
          # Unsorted path: ONE COUNT on the scoped relation + a LIMITed fetch,
          # never a full load just to render 50 rows.
          if games.is_a?(Array)
            total = games.size
            rows  = games.first(page)
          else
            total = games.count
            rows  = games.limit(page).to_a
          end
          payload = Pito::MessageBuilder::Game::List.call(rows, conversation:, columns:, channels: set_channels, suppressed_columns:)
          if total > page
            cursor = games_cursor(page, sort, columns, suppressed_columns)
            payload["list_cursor"] = cursor
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: total,
              rest:  total - rows.size,
              tool:  Pito::Dispatch::Config.pager(tool: :list)[:more_tool]
            )
            payload["list_footer"] = [ payload["list_footer"].presence, more_text ].compact.join(" ")
          end
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        # Resolves the listable noun from the head by walking its tokens through
        # the shared :nouns vocabulary.
        #
        # Returns [canonical, correction_or_nil] where:
        #   - canonical  — one of "channels" / "vids" / "games", or nil (games path)
        #   - correction — { original:, canonical: } when fuzzy resolution fired, else nil
        #
        # Exact + synonym matches return nil correction (no note needed).
        # resolve_fuzzy is tried once the first fuzzy hit is found — only the
        # first near-miss per head is reported.
        # The tool token itself never resolves, so it is skipped naturally.
        def detected_noun(head)
          vocab             = Pito::Grammar::Registry.vocabulary(:nouns)
          fuzzy_correction  = nil
          head.to_s.downcase.split(/\s+/).each do |token|
            canonical = vocab.resolve(token)
            return [ canonical, nil ] if canonical
            if fuzzy_correction.nil?
              fuzzy = vocab.resolve_fuzzy(token)
              fuzzy_correction = { original: token, canonical: fuzzy } if fuzzy
            end
          end
          fuzzy_correction ? [ fuzzy_correction[:canonical], fuzzy_correction ] : [ nil, nil ]
        end

        # Prepends a short note event when a fuzzy correction fired.
        # No-op when correction is nil, result is not Ok, or events are empty.
        def prepend_typo_note(result, correction)
          return result unless correction && result.is_a?(Pito::Chat::Result::Ok) && result.events.any?

          note_text  = Pito::Copy.render(
            "pito.copy.grammar.typo_correction",
            original: correction[:original], canonical: correction[:canonical]
          )
          note_event = { kind: :system, payload: { "text" => note_text } }
          Pito::Chat::Result::Ok.new(events: [ note_event ] + result.events)
        end

        # With no `with` clause, auto-fill the first N canonical columns, where N
        # is the width-derived budget. COLUMNS.keys is already canonical order, so
        # this respects it. Explicit `with` columns bypass this entirely.
        #
        # @param exclude [Array<Symbol>] columns dropped from the CANDIDATE pool
        #   before the budget is applied (e.g. :channel on a single-channel
        #   list) — excluding up front, rather than stripping the filled result
        #   after the fact, lets the budget naturally promote the next
        #   canonical column instead of coming up short (owner: "auto_filled_columns
        #   naturally promotes the next canonical column into the budget —
        #   assert that, do not fight it").
        def auto_filled_columns(list_columns, exclude: [])
          # Skip internal columns (e.g. Video's slate-only :scheduled) — auto-fill
          # only ever surfaces user-facing columns.
          all_cols = list_columns::COLUMNS.reject { |_, cfg| cfg[:internal] }.keys - exclude
          cap      = [ all_cols.size, MAX_AUTOFILL_COLS ].min
          all_cols.first(column_budget(cap))
        end

        # Number of columns the scrollback width can hold — 0 when the width is
        # unknown or too narrow (keeps the lean id+title default), capped at `max`
        # so a very wide viewport simply shows them all.
        def column_budget(max)
          width = viewport_width.to_i
          return 0 if width <= 0

          ((width - COLUMN_BASE_PX) / COLUMN_PER_PX).clamp(0, max)
        end

        # `list videos [published|unlisted|scheduled|private] [with <col>, …]`
        #
        # 1. Resolve channel scope from `self.channel`.
        # 2. Apply privacy filter from raw input.
        # 3. Parse extra columns from `with` clause.
        # 4. Order by title ASC; eager-load associations needed for columns.
        def list_videos
          ids = explicit_ids

          if ids.any?
            # `list videos 2, #4, 7` → exactly those vids (channel scope + privacy
            # filter bypassed — you named the rows), in the typed order.
            scoped = ::Video.where(id: ids)
          else
            # Resolve channel scope.
            scoped, error = channel_scoped_videos
            return error if error

            # Apply privacy filter.
            filter_key = visibility_filter_from(message.raw)
            scoped     = scoped.public_send(filter_key) if filter_key
          end

          # F-2 (same shape as #list_games): "list vids with hard bosses"
          # must reach the NL gate, not render the full unfiltered list.
          return unknown_entity if unrecognized_with_filter?(message.raw, vocabulary: Pito::MessageBuilder::Video::ListColumns.vocabulary)

          # Single-channel suppression + intro reference — decided ONCE from the
          # FULL un-paginated scope, never per-page (see #video_channel_context).
          # An explicit id list bypasses channel scope entirely, so it is never
          # treated as single-channel "by definition" even when a channel
          # context happens to be set (`ids.any?` → known_channel: nil below).
          set_channels, suppressed_columns = video_channel_context(
            scoped, known_channel: ids.any? ? nil : channel_scope_object
          )

          # Parse extra columns; excluding suppressed ones from the auto-fill
          # candidate pool lets the width budget promote the next canonical
          # column instead of coming up short. An explicit `with channel` is
          # stripped just the same right after (post-hoc — no "budget" to
          # protect there).
          columns = Pito::Chat::WithColumns.parse(
            message.raw,
            vocabulary: Pito::MessageBuilder::Video::ListColumns.vocabulary
          )
          columns = auto_filled_columns(Pito::MessageBuilder::Video::ListColumns, exclude: suppressed_columns) if columns.empty?
          columns -= suppressed_columns

          # Order; always eager-load :channel; also load :linked_games and :stats
          # when extra columns are requested to avoid N+1 queries.
          videos = self.class.videos_relation(scoped, columns:)

          if videos.empty?
            return videos_empty(channel)
          end

          # Explicit-id list: render exactly those, in the typed order, unpaginated.
          return videos_by_ids_result(videos, ids, columns, channels: set_channels, suppressed_columns:) if ids.any?

          sort = Pito::Chat::SortClause.parse(message.raw)
          if sort
            key = Pito::MessageBuilder::Video::ListColumns.sort_key_for(
              sort[:token], selected_columns: columns
            )
            if key.nil?
              payload = Pito::MessageBuilder::Text.call(
                "pito.copy.list.sort_column_not_visible",
                column: sort[:token]
              )
              return Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
            end
            videos = videos.to_a.sort_by { |v| key.call(v) }
            videos.reverse! if sort[:direction] == :desc
          end

          page = page_size
          # Same shape as the games path: sorted branch is already an Array;
          # unsorted branch pays ONE COUNT + a LIMITed fetch, never a full load.
          if videos.is_a?(Array)
            total = videos.size
            rows  = videos.first(page)
          else
            total = videos.count
            rows  = videos.limit(page).to_a
          end
          payload = Pito::MessageBuilder::Video::List.call(rows, conversation:, columns:, channels: set_channels, suppressed_columns:)
          if total > page
            cursor = video_cursor(page, sort, columns, filter_key, suppressed_columns)
            payload["list_cursor"] = cursor
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: total,
              rest:  total - rows.size,
              tool:  Pito::Dispatch::Config.pager(tool: :list)[:more_tool]
            )
            payload["list_footer"] = [ payload["list_footer"].presence, more_text ].compact.join(" ")
          end
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        # `list <noun> <ids>` → the named rows in the typed order, unpaginated (an
        # explicit id set is a bounded pick, not a page to walk).
        def videos_by_ids_result(videos, ids, columns, channels:, suppressed_columns:)
          rows    = id_ordered(videos.to_a, ids)
          payload = Pito::MessageBuilder::Video::List.call(rows, conversation:, columns:, channels:, suppressed_columns:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        # `list games 2, #4, 7` → exactly those games in the typed order. An
        # explicit id set bypasses channel scope entirely (same reasoning as
        # the vids ids path), so channel context is always freshly queried —
        # never the resolved_channel_handle shortcut.
        def games_by_ids_result(ids)
          set_channels       = self.class.channel_handles_for_games(ids)
          suppressed_columns = set_channels.size == 1 ? [ :channels ] : []

          columns = Pito::Chat::WithColumns.parse(
            message.raw, vocabulary: Pito::MessageBuilder::Game::ListColumns.vocabulary
          )
          columns = auto_filled_columns(Pito::MessageBuilder::Game::ListColumns, exclude: suppressed_columns) if columns.empty?
          columns -= suppressed_columns

          games   = self.class.games_relation(::Game.where(id: ids), columns:)
          return games_empty if games.empty?

          rows    = id_ordered(games.to_a, ids)
          payload = Pito::MessageBuilder::Game::List.call(rows, conversation:, columns:, channels: set_channels, suppressed_columns:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        # Returns [relation, nil] or [nil, Result::Ok(error event)] for unknown handle.
        # Scopes a games relation to only games with ≥1 linked video on the resolved channel.
        def scope_games_to_channel(games)
          handle = resolved_channel_handle
          return [ games, nil ] if handle.nil?

          ch = self.class.find_channel_by_handle(handle)
          if ch.nil?
            error_payload = Pito::MessageBuilder::Text.call(
              "pito.copy.channels.not_found",
              handle: handle
            )
            return [ nil, Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: error_payload }
            ]) ]
          end

          [ self.class.games_scoped_to_channel(games, ch), nil ]
        end

        # Returns [relation, nil] or [nil, Result::Ok(error event)] for unknown handle.
        def channel_scoped_videos
          handle = resolved_channel_handle

          if handle.nil?
            # @all or blank → all channels
            return [ ::Video.all, nil ]
          end

          # Channel handles may be stored with or without leading "@".
          # Normalise both sides by stripping leading "@" before comparing.
          ch = self.class.find_channel_by_handle(handle)
          if ch.nil?
            error_payload = Pito::MessageBuilder::Text.call(
              "pito.copy.videos.channel_not_found",
              handle: handle
            )
            return [ nil, Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: error_payload }
            ]) ]
          end

          [ ch.videos, nil ]
        end

        # Returns the handle string when the channel filter is a specific channel,
        # or nil when it is "@all" / blank / nil (meaning no channel scope).
        def resolved_channel_handle
          ch = channel.to_s.strip
          return nil if ch.blank? || ch.casecmp("@all").zero?

          ch
        end

        # The Channel object for a resolved handle scope (`list vids @handle` /
        # `list games @handle`), or nil — @all / no channel context / an
        # unresolvable handle (channel_scoped_videos/scope_games_to_channel
        # already render the not-found error before this is ever consulted).
        def channel_scope_object
          handle = resolved_channel_handle
          return nil if handle.nil?

          self.class.find_channel_by_handle(handle)
        end

        # Distinct @handles + the single-channel suppression decision for a
        # video list — the FULL un-paginated `scoped` relation drives both, so
        # they can never disagree (see .channel_handles_for_videos, the query).
        #
        # @return [[Array<String>, Array<Symbol>]] [set_channels, suppressed_columns]
        def video_channel_context(scoped, known_channel:)
          handles = self.class.channel_handles_for_videos(scoped, known_channel:)
          [ handles, handles.size == 1 ? [ :channel ] : [] ]
        end

        # Same contract as #video_channel_context, for games — reaches channels
        # through the games' linked vids (a game carries no channel of its own).
        # Skips plucking ids entirely when known_channel is already resolved
        # (the shortcut never needs them).
        #
        # @return [[Array<String>, Array<Symbol>]] [set_channels, suppressed_columns]
        def game_channel_context(games, known_channel:)
          ids     = known_channel ? [] : (games.is_a?(Array) ? games.map(&:id) : games.pluck(:id))
          handles = self.class.channel_handles_for_games(ids, known_channel:)
          [ handles, handles.size == 1 ? [ :channels ] : [] ]
        end

        # Returns the Symbol scope name (:published / :unlisted / :scheduled /
        # :private_unscheduled) or nil.
        def visibility_filter_from(raw)
          VISIBILITY_FILTERS.each do |word, scope|
            return scope if raw.match?(/\b#{Regexp.escape(word)}\b/i)
          end
          nil
        end

        # Empty-state for videos — distinct copy per channel-scoped vs. global.
        def videos_empty(ch)
          handle = resolved_channel_handle

          if handle
            payload = Pito::MessageBuilder::Text.call(
              "pito.copy.videos.list_empty_channel",
              channel: ch.to_s
            )
          else
            payload = Pito::MessageBuilder::Text.call("pito.copy.videos.list_empty")
          end

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        # `list channels` → the channels kv-table (Avatar/Handle/Title/Subs/Views/
        # Vids — Pito::MessageBuilder::Channel::List). Default order = latest upload
        # activity; a `sort <col> [desc]` clause re-orders by any column except
        # Avatar (no with/without — all columns are always shown). If any connected
        # channel's youtube_connection needs reauth, appends a second :enhanced
        # event listing those channels with a reconnect hint.
        def list_channels
          # Guard: only connected channels (a youtube_connection). A connection-less
          # orphan row (stray/test data) is never a real channel — never list it.
          channels = self.class.channels_relation
          if channels.empty?
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.channels.list_empty") }
            ])
          end

          channels = channels.to_a

          # Selected columns: the defaults (subs/views/vids) plus any
          # `with <col>` additions — stamped into the payload so the reply
          # levers (`#h without views`) can slim the DEFAULT set too.
          columns = Pito::MessageBuilder::Channel::ListColumns::DEFAULT_COLUMNS |
                    Pito::Chat::WithColumns.parse(
                      message.raw,
                      vocabulary: Pito::MessageBuilder::Channel::ListColumns.vocabulary
                    )

          sort = Pito::Chat::SortClause.parse(message.raw)
          if sort
            key = Pito::MessageBuilder::Channel::ListColumns.sort_key_for(
              sort[:token], selected_columns: columns
            )
            if key.nil?
              payload = Pito::MessageBuilder::Text.call(
                "pito.copy.channels.sort_unknown_column",
                column: sort[:token]
              )
              return Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
            end
            channels = channels.sort_by { |c| key.call(c) }
            channels.reverse! if sort[:direction] == :desc
          end

          page    = page_size
          rows    = channels.first(page)
          payload = Pito::MessageBuilder::Channel::List.call(rows, conversation:, columns:)
          if channels.size > page
            cursor = channels_cursor(page, sort, columns)
            payload["list_cursor"] = cursor
            total = channels.size
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: total,
              rest:  total - rows.size,
              tool:  Pito::Dispatch::Config.pager(tool: :list)[:more_tool]
            )
            existing_footer = payload["list_footer"].to_s.presence
            payload["list_footer"] = [ existing_footer, more_text ].compact.join(" ")
          end
          events  = [ { kind: :system, payload: } ]

          reauth = rows.select { |c| c.youtube_connection&.needs_reauth? }
          if reauth.any?
            events << { kind: :enhanced, payload: Pito::MessageBuilder::Channel::ReauthNeeded.call(reauth) }
          end

          Pito::Chat::Result::Ok.new(events:)
        end

        def games_list_help
          payload = Pito::MessageBuilder::Game::ListHelp.call
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        # Number of days that splits "soon" (imminent) from "later" (distant/TBA).
        UPCOMING_SOON_DAYS = 30

        # `list games upcoming` → a horizon-split PAIR, ALWAYS both messages.
        # Games with a release_date within the next 30 days form the :system "soon"
        # card; everything else — later-dated OR undated/TBA — forms the :enhanced
        # "later" card. An EMPTY bucket still emits its message, with an ironic
        # empty-state intro (distinct per bucket). Each carries the horizon as a
        # subject-token.
        def list_games_upcoming(games, columns:)
          boundary = Date.current + UPCOMING_SOON_DAYS
          soon, later = games.to_a.partition { |g| g.release_date.present? && g.release_date <= boundary }
          soon  = soon.sort_by  { |g| [ g.release_date, g.title.to_s ] }
          later = later.sort_by { |g| [ g.release_date ? 0 : 1, g.release_date || Date.new(9999), g.title.to_s ] }

          Pito::Chat::Result::Ok.new(events: [
            upcoming_event(kind: :system, games: soon, columns:, horizon: "the next 30 days",
                           intro_key: "pito.copy.games.upcoming.soon.intro",
                           empty_key: "pito.copy.games.upcoming.soon.empty"),
            upcoming_event(kind: :enhanced, games: later, columns:, horizon: "someday",
                           intro_key: "pito.copy.games.upcoming.later.intro",
                           empty_key: "pito.copy.games.upcoming.later.empty")
          ])
        end

        # One upcoming card: the game list with its horizon intro when the bucket
        # has games; otherwise an html message carrying only the ironic empty-state
        # copy (no table).
        def upcoming_event(kind:, games:, columns:, horizon:, intro_key:, empty_key:)
          payload =
            if games.any?
              Pito::MessageBuilder::Game::List.call(
                games, conversation:, columns:, intro: upcoming_intro(intro_key, horizon)
              )
            else
              { "html" => true, "body" => upcoming_intro(empty_key, horizon) }
            end
          { kind:, payload: }
        end

        # The intro/empty copy: horizon as a purple→blue SUBJECT shimmer token.
        def upcoming_intro(key, horizon)
          Pito::Copy.render_html(key, { horizon: }, shimmer: [ :horizon ])
        end

        def games_empty
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.list_empty") }
          ])
        end

        def games_filter_empty
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.list_filter_empty") }
          ])
        end

        # `list <typo>` — a token was fuzzy-close to a real genre/platform/noun
        # term. Offer the correction(s) instead of listing, surfacing them as a
        # single :system event so the owner can re-type the fixed command.
        def did_you_mean(suggestions)
          payload = Pito::MessageBuilder::Text.call(
            "pito.copy.list.did_you_mean",
            suggestions: suggestions.map { |s| "`#{s}`" }.join(", ")
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        # True when the (clause-stripped) head carries a token outside the known
        # list vocabulary — see `unrecognized_head_token?` callsite for the no-guess
        # rationale.
        def unrecognized_head_token?(head)
          head.to_s.downcase.split(/\s+/).reject(&:blank?).any? do |token|
            !Pito::Chat::GameListFilter.recognized?(token)
          end
        end

        # The always-rendered base columns — legal `with` no-ops, never a
        # reroute: "list games with title" asks for what the list already
        # shows, which is not free text.
        BASE_COLUMN_TOKENS = %w[id title].freeze

        # See the F-2 comment at its callsite in #list_games (the vids
        # callsite mirrors it). Reroutes ONLY an entirely-alien clause: a
        # clause that ALSO names at least one real column is column intent
        # with junk to drop — G26.1 pins that the removed legacy `comments`
        # token keeps degrading gracefully next to valid columns ("with
        # views,comments,game" stays a column list); "with hard bosses"
        # (nothing recognized) reads as free text for the NL gate.
        def unrecognized_with_filter?(raw, vocabulary:)
          leftovers = Pito::Chat::WithColumns.unrecognized(raw, vocabulary: vocabulary)
                                             .reject { |token| BASE_COLUMN_TOKENS.include?(token) }
          return false if leftovers.empty?

          Pito::Chat::WithColumns.parse(raw, vocabulary: vocabulary).empty?
        end

        # Free-chat with a genuinely unknown word — no guessing.
        # Render the generic "I don't get it" dictionary (`pito.copy.huh`, reused per
        # owner). Pre-rendered so the finalizer routes it to `text:` (keeps :error chrome).
        #
        # NL soft-fail (3.0.1 P7): in free chat this branch used to render the
        # huh copy WITHOUT consulting NL — flag the error as an nl_fallback
        # marker so Pito::Dispatch::Router gives the ORIGINAL utterance one shot
        # at the NL gate first (its own below-suggest fallback is this same huh
        # copy). Follow-up replies (machine-reconstructed input) stay a plain
        # error, as does the marker itself when it degrades un-fallen-back.
        def unknown_entity
          Pito::Chat::Result::Error.new(
            message_key: Pito::Copy.render("pito.copy.huh"), message_args: {}, nl_fallback: !follow_up? && nl_eligible?
          )
        end

        # ── Pager helpers ─────────────────────────────────────────────────────

        # Returns the configured page size from the YAML tool ontology.
        # Never hardcode 50 — read it here so a config change propagates to all
        # three list surfaces uniformly.
        def page_size
          Pito::Dispatch::Config.pager(tool: :list)[:page_size]
        end

        # Continuation cursor for a video list page. Stores everything the `next`
        # follow-up handler needs to re-run the same query from +offset+:
        # channel scope, visibility filter, sort clause, and column selection.
        # `nil` filter means no visibility filter (all statuses); `nil` channel
        # means @all (no channel scope). `suppressed_columns` carries page 1's
        # single-channel decision forward so later pages never re-offer or
        # re-add the column (it is never re-derived per page).
        def video_cursor(offset, sort, columns, filter_key, suppressed_columns = [])
          {
            "offset"             => offset,
            "channel"            => resolved_channel_handle,
            "filter"             => filter_key&.to_s,
            "sort_token"         => sort&.dig(:token),
            "sort_direction"     => sort&.dig(:direction)&.to_s,
            "columns"            => columns.map(&:to_s),
            "suppressed_columns" => Array(suppressed_columns).map(&:to_s)
          }
        end

        # Continuation cursor for a games list page. Stores the full
        # `message.raw` so the `next` handler can replay
        # `GameListFilter.call(cursor["raw"])` with the identical genre/platform/
        # upcoming tokens — GameListFilter ignores unrecognised tokens silently,
        # so the sort clause and `with` column tokens in the raw string are safe.
        # `suppressed_columns` — see #video_cursor.
        def games_cursor(offset, sort, columns, suppressed_columns = [])
          {
            "offset"             => offset,
            "raw"                => message.raw,
            "channel"            => resolved_channel_handle,
            "sort_token"         => sort&.dig(:token),
            "sort_direction"     => sort&.dig(:direction)&.to_s,
            "columns"            => columns.map(&:to_s),
            "suppressed_columns" => Array(suppressed_columns).map(&:to_s)
          }
        end

        # Continuation cursor for a channels list page. Channels have no per-column
        # filter or channel scope — only sort state is required to rerun the query.
        def channels_cursor(offset, sort, columns = [])
          {
            "offset"         => offset,
            "sort_token"     => sort&.dig(:token),
            "sort_direction" => sort&.dig(:direction)&.to_s,
            "columns"        => Array(columns).map(&:to_s)
          }
        end
      end
    end
  end
end
