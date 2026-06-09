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
# Syntax: `list videos [published|unlisted]`
#
# Channel scope comes from `self.channel` (the param threaded through the
# dispatcher, e.g. "@all" or "@handle"):
#   "@all" (or nil/blank) → all channels.
#   "@<handle>"           → videos for that channel only; unknown handle → error.
#
# Privacy filter:
#   "published" → Video.published (public)
#   "unlisted"  → Video.unlisted
#   (none)      → all videos regardless of privacy_status
#
# Ordering: title ASC (consistent with games + channels listing).
#
# Follow-up: NOT stamped (no video_list follow-up handler; simplest consistent
# choice matching the absence of a `video_list` follow-up engine).
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

        PRIVACY_FILTERS = {
          "published" => :published,
          "unlisted"  => :unlisted
        }.freeze

        def call
          return list_channels if message.raw.match?(/\bchannels?\b/i)
          return list_videos   if message.raw.match?(/\bvideos?\b/i)

          filtered = Pito::Chat::GameListFilter.filtered?(message.raw)
          columns  = Pito::Chat::WithColumns.parse(
            message.raw,
            vocabulary: Pito::MessageBuilder::Game::ListColumns.vocabulary
          )
          games    = Pito::Chat::GameListFilter.call(message.raw)

          games, error = scope_games_to_channel(games)
          return error if error

          channel_scoped = resolved_channel_handle.present?

          games = games.includes(:genres, :developer_companies, :publisher_companies) if columns.any?

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

        # `list videos [published|unlisted] [with <col>, …]`
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
          filter_key = privacy_filter_from(message.raw)
          scoped     = scoped.public_send(filter_key) if filter_key

          # Parse extra columns.
          columns = Pito::Chat::WithColumns.parse(
            message.raw,
            vocabulary: Pito::MessageBuilder::Video::ListColumns.vocabulary
          )

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

        # Returns the Symbol scope name (:published / :unlisted) or nil.
        def privacy_filter_from(raw)
          PRIVACY_FILTERS.each do |word, scope|
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
        def list_channels
          channels = ::Channel.order(:title)
          if channels.empty?
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.channels.list_empty") }
            ])
          end

          payload = Pito::MessageBuilder::Channel::List.call(channels, conversation:)

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
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
      end
    end
  end
end
