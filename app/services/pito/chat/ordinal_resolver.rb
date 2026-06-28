# frozen_string_literal: true

module Pito
  module Chat
    # Resolves the chronologically first or last Game or Video that matches
    # optional filters and a shift+tab channel scope.
    #
    # Used by `show first|last [<genre>] game` and
    #            `show first|last [<privacy>] vid`.
    #
    # All-time scope — never windowed by the shift+space analytics period.
    #
    # Ordering attributes:
    #   Game  → release_date ASC (first = oldest) / DESC (last = newest); NULLs last.
    #   Video → published_at  ASC / DESC;                                  NULLs last.
    #
    # Channel scope (shift+tab):
    #   "@all" / nil / blank → no channel filter (across all channels).
    #   "@handle"            → Game:  games linked via video_game_links to that channel's videos.
    #                          Video: that channel's videos only.
    #   Unknown handle       → returns nil (caller treats this as entity not found).
    class OrdinalResolver
      # Maps lower-cased privacy word tokens to Video scope method names.
      # Referenced by the Show handler for token parsing, and here for scope dispatch.
      # When no privacy token is present the resolver defaults to :published, matching
      # the alias rule: `show last vid` = `show last published vid`.
      VIDEO_PRIVACY_FILTERS = {
        "published" => :published,
        "public"    => :published,
        "unlisted"  => :unlisted,
        "private"   => :privacy_status_private
      }.freeze

      # @param entity        [Symbol]       :game or :video
      # @param ordinal       [Symbol]       :first or :last
      # @param filters       [Hash]
      #   Game:  { genre:   String | nil }  — genre substring (from GameListFilter::GENRE_ALIASES);
      #                                        nil → no genre filter.
      #   Video: { privacy: Symbol | nil }  — scope method symbol (see VIDEO_PRIVACY_FILTERS);
      #                                        nil → defaults to :published.
      # @param channel_scope [String, nil]  raw channel attribute value: "@handle", "@all", nil, or ""
      # @return [::Game, ::Video, nil]
      def self.call(entity:, ordinal:, filters:, channel_scope:)
        new(entity:, ordinal:, filters:, channel_scope:).call
      end

      def initialize(entity:, ordinal:, filters:, channel_scope:)
        @entity        = entity
        @ordinal       = ordinal
        @filters       = filters
        @channel_scope = channel_scope
      end

      def call
        case @entity
        when :game  then resolve_game
        when :video then resolve_video
        end
      end

      private

      # ── Game resolution ──────────────────────────────────────────────────────

      def resolve_game
        relation = ::Game.all

        # Genre filter: match a genre name substring (same logic as GameListFilter).
        if (genre_sub = @filters[:genre])
          relation = relation.joins(:genres)
                             .where("genres.name ILIKE ?", "%#{genre_sub}%")
                             .distinct
        end

        # Channel scope: restrict to games with ≥1 linked video on that channel.
        ch = channel_record
        return nil if ch == :not_found

        if ch
          relation = relation.joins(video_game_links: :video)
                             .where(videos: { channel_id: ch.id })
                             .distinct
        end

        relation.order(Arel.sql("release_date #{order_direction} NULLS LAST")).first
      end

      # ── Video resolution ─────────────────────────────────────────────────────

      def resolve_video
        # Default privacy: :published — fulfils the alias rule
        # `show last vid` = `show last published vid`.
        privacy  = @filters[:privacy] || :published
        relation = ::Video.public_send(privacy)

        # Channel scope: restrict to that channel's videos only.
        ch = channel_record
        return nil if ch == :not_found

        relation = relation.where(channel_id: ch.id) if ch

        relation.order(Arel.sql("published_at #{order_direction} NULLS LAST")).first
      end

      # ── Shared helpers ───────────────────────────────────────────────────────

      # "ASC" for :first (earliest), "DESC" for :last (newest).
      def order_direction
        @ordinal == :first ? "ASC" : "DESC"
      end

      # Resolves the channel scope to one of three outcomes:
      #   nil        → no channel scope (@all / blank / nil); apply no filter.
      #   Channel    → found; scope the relation to this channel.
      #   :not_found → handle given but no DB row matches; caller returns nil.
      def channel_record
        ch_str = @channel_scope.to_s.strip
        return nil if ch_str.blank? || ch_str.casecmp("@all").zero?

        norm = ch_str.sub(/\A@+/, "").downcase
        ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm) || :not_found
      end
    end
  end
end
