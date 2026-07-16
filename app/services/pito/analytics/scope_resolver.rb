# frozen_string_literal: true

module Pito
  module Analytics
    # Resolves an `analyze` command into the set of scope entities to analyze and
    # the presentation level, applying the owner's shift+tab (channel scope) and
    # entity-argument rules. The shift+space PERIOD is NOT resolved here — it is
    # threaded separately to the fetch/aggregation layer.
    #
    # Rules:
    #   bare `analyze`              → :suggest (show options; do nothing)
    #   analyze channel            → shift+tab (@all → all channels; else that one)
    #   analyze channel @h         → that channel (ignore shift+tab)
    #   analyze channels @h1,@h2   → those channels (ignore shift+tab)
    #   analyze @h                 → same as `analyze channel @h` (no noun
    #                                needed — a bare @handle is unambiguous)
    #   analyze vids               → == analyze channel (shift+tab)
    #   analyze vids #1,#2         → those vids (ignore shift+tab)
    #   analyze games #1,#2        → those games (presented at game level)
    #   analyze games (no ids)     → shift+tab channels → their videos → linked games
    #
    # Result:
    #   status  :ok | :suggest | :error
    #   level   :channel | :vid | :game            (when :ok)
    #   scopes  Array<Channel|Video|Game>          (when :ok; entities to analyze)
    #   error_key (Symbol) / error_args (Hash)     (when :error; handler maps to copy)
    class ScopeResolver
      ALL = "@all"

      Result = Data.define(:status, :level, :scopes, :error_key, :error_args) do
        def ok?      = status == :ok
        def suggest? = status == :suggest
        def error?   = status == :error
      end

      def self.call(raw:, channel_scope:)
        new(raw:, channel_scope:).call
      end

      def initialize(raw:, channel_scope:)
        @raw           = raw.to_s
        @channel_scope = channel_scope.to_s.strip
      end

      def call
        case detected_noun
        when "channels" then resolve_channels
        when "vids"     then resolve_vids
        when "games"    then resolve_games
        else suggest # bare `analyze` (no entity word) → suggest options, no-op
        end
      end

      private

      # ── entity routing ──────────────────────────────────────────────────────────

      def resolve_channels
        handles = explicit_handles
        return scope_channels if handles.empty? || handles == [ ALL ]

        channels, missing = lookup_channels(handles)
        return error(:channels_not_found, handles: missing.join(", ")) if missing.any?

        ok(:channel, channels)
      end

      def resolve_vids
        ids = explicit_ids
        return scope_channels if ids.empty? # bare `vids` == `analyze channel`

        vids, missing = lookup_by_id(::Video, ids)
        return error(:vids_not_found, ids: join_ids(missing)) if missing.any?

        ok(:vid, vids)
      end

      def resolve_games
        ids = explicit_ids
        if ids.any?
          games, missing = lookup_by_id(::Game, ids)
          return error(:games_not_found, ids: join_ids(missing)) if missing.any?

          return ok(:game, games)
        end

        # bare `games` → shift+tab channels → their videos → linked games
        channels, error_result = scope_channel_records
        return error_result if error_result

        games = ::Game
          .joins(video_game_links: :video)
          .where(videos: { channel_id: channels.map(&:id) })
          .distinct
          .to_a
        ok(:game, games)
      end

      # ── shift+tab channel scope ──────────────────────────────────────────────────

      # :ok at :channel level from the shift+tab scope (bare `channel` and bare `vids`).
      def scope_channels
        channels, error_result = scope_channel_records
        return error_result if error_result

        ok(:channel, channels)
      end

      # [channels, nil] or [nil, error Result]. @all (or blank) → all channels.
      def scope_channel_records
        return [ ::Channel.all.to_a, nil ] if all_scope?

        ch = lookup_channel(@channel_scope)
        return [ nil, error(:channel_not_found, handle: @channel_scope) ] if ch.nil?

        [ [ ch ], nil ]
      end

      def all_scope?
        @channel_scope.blank? || @channel_scope.casecmp(ALL).zero?
      end

      # ── parsing ──────────────────────────────────────────────────────────────────

      def detected_noun
        vocab = Pito::Grammar::Registry.vocabulary(:nouns)
        @raw.downcase.split(/\s+/).each do |token|
          canonical = vocab.resolve(token)
          return canonical if canonical
        end

        # No noun word typed ("analyze @gmrdad82", no "channel"/"channels"):
        # an @handle unambiguously names a channel — vids/games resolve by
        # numeric id only, so a bare handle can never mean anything else.
        # Without this (3.0.1 P11), a leading @handle with no noun silently
        # fell through to `suggest` ("Analyze what?"), dropping the typed
        # handle on the floor.
        return "channels" if explicit_handles.any?

        nil
      end

      # Numeric refs: `#1`, `1`, comma- or space-separated. A period token never
      # appears in an analyze command (period comes from shift+space), so a bare
      # digit scan is safe.
      def explicit_ids
        @raw.scan(/#?(\d+)/).flatten.map(&:to_i).uniq
      end

      def explicit_handles
        @raw.scan(/@[A-Za-z0-9_.\-]+/).map(&:downcase).uniq
      end

      # ── lookups ──────────────────────────────────────────────────────────────────

      def lookup_by_id(model, ids)
        found     = model.where(id: ids).to_a
        found_ids = found.map(&:id)
        [ found, ids - found_ids ]
      end

      def lookup_channels(handles)
        found   = []
        missing = []
        handles.each do |h|
          ch = lookup_channel(h)
          ch ? (found << ch) : (missing << h)
        end
        [ found, missing ]
      end

      # Mirrors the SAME resolution `::Channel.resolve_handle` already gives
      # `show channel <handle>` and the `:channel_by_handle` reply resolver
      # (3.0.1 P11) — exact @-agnostic match, then a pg_trgm fuzzy fallback —
      # instead of the narrower exact-only query this method used to
      # reimplement inline.
      def lookup_channel(handle)
        ::Channel.resolve_handle(handle)
      end

      # ── result builders ──────────────────────────────────────────────────────────

      def ok(level, scopes)
        Result.new(status: :ok, level:, scopes: Array(scopes), error_key: nil, error_args: nil)
      end

      def suggest
        Result.new(status: :suggest, level: nil, scopes: [], error_key: nil, error_args: nil)
      end

      def error(key, **args)
        Result.new(status: :error, level: nil, scopes: [], error_key: key, error_args: args)
      end

      def join_ids(ids) = ids.map { |i| "##{i}" }.join(", ")
    end
  end
end
