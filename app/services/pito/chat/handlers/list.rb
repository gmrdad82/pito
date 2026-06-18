# frozen_string_literal: true

# Handler for the `list` chat verb — games, channels, and videos.
#
# Dispatches based on the noun in the raw input:
#   `list` / `list games`   → game library (title-sorted, filterable, follow-up-able)
#   `list channels`         → connected channel cards
#   `list videos [filter]`  → video list, scoped by channel filter + optional privacy
#
# ## Video listing
#
# Syntax: `list videos [published|unlisted|scheduled]`
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
#   (none)      → all videos regardless of privacy_status
#
# Ordering: title ASC (consistent with games + channels listing).
#
# Follow-up: video list IS stamped as `reply_target: "video_list"`, enabling
# follow-up reply verbs (show, delete, link, unlink, add, remove, sort/order).
#
# NOTE: `game`/`games` are FILLER words in the grammar, so `list` and
# `list games` parse identically — both land here.
#
# Filtering syntax for games: `list games [upcoming] [<genres>…] [<platforms>…]`
# All parts optional, order-independent. See Pito::Chat::GameListFilter.
module Pito
  module Chat
    module Handlers
      class List < Pito::Chat::Handler
        self.verb = :list
        self.description_key = "pito.chat.list.descriptions.list"

        VISIBILITY_FILTERS = {
          "published" => :published,
          "unlisted"  => :unlisted,
          "scheduled" => :scheduled
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

        def call
          # The noun (channels/videos/games) is whatever precedes the first clause
          # keyword. A `with <columns>` clause may legitimately contain "channels"
          # (the games Channels column) or "video", which must NOT be mistaken for
          # the noun — otherwise `list games with channels` routes to `list channels`.
          head = noun_head(message.raw)
          return list_channels  if head.match?(/\bchannels?\b/i)
          # Require the plural "videos" — "list video" (singular) is NOT a valid
          # noun and falls through to the unknown-noun handler below.
          return list_videos    if head.match?(/\bvideos\b/i)
          return games_list_help if message.raw.match?(/(?:\A|\s)--help(?:\s|\z)/)

          # Reject an unrecognized noun (e.g. `list asd`) instead of silently
          # listing all games. Checked against the head only, so `with <columns>`
          # / `sorted by` clauses never trip it.
          unknown = Pito::Chat::GameListFilter.unrecognized_tokens(head)
          return unknown_list_target(unknown) if unknown.any?

          filtered = Pito::Chat::GameListFilter.filtered?(message.raw)
          columns  = Pito::Chat::WithColumns.parse(
            message.raw,
            vocabulary: Pito::MessageBuilder::Game::ListColumns.vocabulary
          )
          columns  = auto_filled_columns(Pito::MessageBuilder::Game::ListColumns) if columns.empty?
          games    = Pito::Chat::GameListFilter.call(message.raw)

          games, error = scope_games_to_channel(games)
          return error if error

          channel_scoped = resolved_channel_handle.present?

          if columns.any?
            includes_args = [ :genres, :developer_companies, :publisher_companies ]
            includes_args << { linked_videos: :channel } if columns.include?(:channels)
            includes_args << :footages if columns.include?(:footage)
            games = games.includes(*includes_args)
          end

          if games.empty?
            return (filtered || channel_scoped) ? games_filter_empty : games_empty
          end

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

          payload = Pito::MessageBuilder::Game::List.call(games, conversation:, columns:)

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        private

        # Returns the part of the raw input that precedes the first clause keyword
        # (`with` / `sorted by` / `ordered by`). The noun is detected from this head
        # so that column names inside a clause (e.g. the games `channels` column)
        # never get read as the `list channels` / `list videos` noun.
        def noun_head(raw)
          raw.to_s.split(/\b(?:with|sorted\s+by|ordered\s+by)\b/i, 2).first.to_s
        end

        # With no `with` clause, auto-fill the first N canonical columns, where N
        # is the width-derived budget. COLUMNS.keys is already canonical order, so
        # this respects it. Explicit `with` columns bypass this entirely.
        def auto_filled_columns(list_columns)
          all_cols = list_columns::COLUMNS.keys
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

        # `list videos [published|unlisted|scheduled] [with <col>, …]`
        #
        # 1. Resolve channel scope from `self.channel`.
        # 2. Apply privacy filter from raw input.
        # 3. Parse extra columns from `with` clause.
        # 4. Order by title ASC; eager-load associations needed for columns.
        def list_videos
          # Resolve channel scope.
          scoped, error = channel_scoped_videos
          return error if error

          # Apply privacy filter.
          filter_key = visibility_filter_from(message.raw)
          scoped     = scoped.public_send(filter_key) if filter_key

          # Parse extra columns.
          columns = Pito::Chat::WithColumns.parse(
            message.raw,
            vocabulary: Pito::MessageBuilder::Video::ListColumns.vocabulary
          )
          columns = auto_filled_columns(Pito::MessageBuilder::Video::ListColumns) if columns.empty?

          # Order; always eager-load :channel; also load :linked_games and :stats
          # when extra columns are requested to avoid N+1 queries.
          includes_args = [ :channel ]
          if columns.any?
            includes_args << :linked_games
            includes_args << :stats
          end
          videos = scoped.includes(*includes_args).order(:title)

          if videos.empty?
            return videos_empty(channel)
          end

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

          payload = Pito::MessageBuilder::Video::List.call(videos, conversation:, columns:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        # Returns [relation, nil] or [nil, Result::Ok(error event)] for unknown handle.
        # Scopes a games relation to only games with ≥1 linked video on the resolved channel.
        def scope_games_to_channel(games)
          handle = resolved_channel_handle
          return [ games, nil ] if handle.nil?

          norm = normalized_handle(handle)
          ch   = ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)
          if ch.nil?
            error_payload = Pito::MessageBuilder::Text.call(
              "pito.copy.channels.not_found",
              handle: handle
            )
            return [ nil, Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: error_payload }
            ]) ]
          end

          scoped = games.joins(video_game_links: :video).where(videos: { channel_id: ch.id }).distinct
          [ scoped, nil ]
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
          norm = normalized_handle(handle)
          ch   = ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)
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

        # Normalise a handle for DB lookup: strip leading @-signs.
        def normalized_handle(handle)
          handle.to_s.sub(/\A@+/, "")
        end

        # Returns the Symbol scope name (:published / :unlisted / :scheduled) or nil.
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

        # `list channels` → inline channel cards rendered by Pito::Channel::ListComponent.
        # Returns a :system event with an html body (intro line + wrapping card strip).
        # If any connected channel's youtube_connection needs reauth, appends a second
        # :enhanced event listing those channels with a reconnect hint.
        def list_channels
          channels = ::Channel.includes(:youtube_connection).order(:title)
          if channels.empty?
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.channels.list_empty") }
            ])
          end

          payload = Pito::MessageBuilder::Channel::List.call(channels, conversation:)
          events  = [ { kind: :system, payload: } ]

          reauth = channels.select { |c| c.youtube_connection&.needs_reauth? }
          if reauth.any?
            events << { kind: :enhanced, payload: Pito::MessageBuilder::Channel::ReauthNeeded.call(reauth) }
          end

          Pito::Chat::Result::Ok.new(events:)
        end

        def games_list_help
          payload = Pito::MessageBuilder::Game::ListHelp.call
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
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

        # `list <unknown>` — the noun is neither channels/videos/games nor a
        # recognized games filter term. Surface an error instead of all games.
        def unknown_list_target(tokens)
          payload = Pito::MessageBuilder::Text.call(
            "pito.copy.list.unknown_target",
            target: tokens.join(" ")
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end
      end
    end
  end
end
