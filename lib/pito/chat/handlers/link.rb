# frozen_string_literal: true

# Handler for `link game <id> to|with video <id>` / `link video <id> to|with game <id>`.
#
# Free-chat: split on ` to ` / ` with ` (case-insensitive) into a left and right half.
# Each half begins with a noun discriminator (`game`/`games` or `video`/`videos`)
# followed by a numeric id (plain or with a leading `#`). Title refs are not
# supported — only local numeric ids.
#
# Follow-up (detail card — singular video_id/game_id in payload):
#   Source is implied by the card entity.  Targets are parsed from everything
#   after the connector word `to`/`with`.  Comma or space separated, multi-target.
#   E.g. `link to 1,2,3` links this video/game to games/videos 1, 2, and 3.
#
# Follow-up (list card — video_ids/game_ids in payload):
#   Source id is on the LEFT of `to`/`with`; targets are on the RIGHT.
#   E.g. `link 17 to 1,2,3` links video/game 17 to games/videos 1, 2, and 3.
#
# Resolution: id-only — `::Game.find_by(id:)` / `::Video.find_by(id:)`.
#
# `VideoGameLink.find_or_create_by!` makes linking idempotent.
# The model's `after_commit` already enqueues game-stats refresh — not duplicated.
module Pito
  module Chat
    module Handlers
      class Link < Pito::Chat::Handler
        include MultiLinkHelpers

        self.tool = :link
        self.description_key = "pito.chat.link.descriptions.link"

        GAME_NOUNS  = %w[game games].freeze
        VIDEO_NOUNS = %w[vid vids video videos].freeze

        def call
          return follow_up_link if follow_up?

          raw = message.body_tokens.map(&:value).join(" ")
          parts = raw.split(/\b(?:to|with)\b/i, 2)

          return usage_hint if parts.size < 2

          left_words  = parts[0].strip.split
          right_words = parts[1].strip.split

          return usage_hint if left_words.empty? || right_words.empty?

          games, videos = resolve_sides(left_words, right_words)
          return games  if result?(games)
          return videos if result?(videos)

          create_links(games, videos)
        end

        private

        # ── Follow-up branch ───────────────────────────────────────────────────

        def follow_up_link
          if video_target?(VIDEO_NOUNS)
            follow_up_multi(
              connectors:    %w[to with],
              source_class:  ::Video,
              other_class:   ::Game,
              source_nouns:  VIDEO_NOUNS,
              other_nouns:   GAME_NOUNS,
              copy_ok:       "pito.copy.games.linked_multi",
              copy_op:       :link
            )
          else
            follow_up_multi(
              connectors:    %w[to with],
              source_class:  ::Game,
              other_class:   ::Video,
              source_nouns:  GAME_NOUNS,
              other_nouns:   VIDEO_NOUNS,
              copy_ok:       "pito.copy.games.linked_multi",
              copy_op:       :link
            )
          end
        end

        # ── Free-chat helpers ──────────────────────────────────────────────────

        # Returns [games, videos] (each an Array of records) — or one slot is a
        # Result::Ok (not-found) / Result::Error (usage hint) to short-circuit.
        # Each side accepts a comma/space-separated id LIST, so
        # `link game 1 with vid 15,14` links game 1 to both vids (cross-product).
        def resolve_sides(left_words, right_words)
          left_noun  = left_words.first.downcase
          right_noun = right_words.first.downcase

          if GAME_NOUNS.include?(left_noun) && VIDEO_NOUNS.include?(right_noun)
            games  = resolve_records(::Game,  left_words.drop(1))
            videos = resolve_records(::Video, right_words.drop(1))
          elsif VIDEO_NOUNS.include?(left_noun) && GAME_NOUNS.include?(right_noun)
            videos = resolve_records(::Video, left_words.drop(1))
            games  = resolve_records(::Game,  right_words.drop(1))
          else
            return [ usage_hint, nil ]
          end

          [ games, videos ]
        end

        # Parses a comma/space-separated numeric id list (each plain or `#`-prefixed)
        # into records. Returns a not-found Result on the first missing id, or the
        # usage hint when no valid id is present.
        def resolve_records(klass, ref_words)
          ids = ref_words.join(" ")
                         .split(/[\s,]+/).map(&:strip)
                         .select { |t| t.match?(/\A#?\d+\z/) }
                         .map { |t| t.delete_prefix("#") }.uniq
          return usage_hint if ids.empty?

          records = []
          ids.each do |id|
            record = klass.find_by(id: id)
            return not_found_for(klass, id) if record.nil?

            records << record
          end
          records
        end

        # ── Shared helpers ─────────────────────────────────────────────────────

        # Links every (game, video) pair (cross-product) idempotently, then a single
        # summary message — the one-pair copy for 1×1, else the multi copy.
        def create_links(games, videos)
          games  = Array(games)
          videos = Array(videos)
          games.product(videos).each { |game, video| VideoGameLink.find_or_create_by!(video:, game:) }

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: link_summary(games, videos) } ])
        end

        def link_summary(games, videos)
          if games.one? && videos.one?
            Pito::MessageBuilder::Text.call("pito.copy.games.linked", game: games.first.title, video: videos.first.title)
          elsif games.one?
            linked_multi(games.first.title, videos.map(&:title))
          elsif videos.one?
            linked_multi(videos.first.title, games.map(&:title))
          else
            linked_multi("#{games.size} games", videos.map(&:title))
          end
        end

        def linked_multi(source, target_titles)
          Pito::MessageBuilder::Text.call(
            "pito.copy.games.linked_multi", source:, targets: target_titles.join(", ")
          )
        end

        def not_found_for(klass, ref)
          klass == ::Game ? not_found_game(ref) : not_found_video(ref)
        end

        def not_found_game(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        def not_found_video(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end

        def usage_hint
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.link.usage",
            message_args: {}
          )
        end

        # True when the value is a Chat::Result (Ok or Error) rather than a record.
        # Used to short-circuit after resolve_other_side.
        def result?(value)
          value.is_a?(Pito::Chat::Result::Ok) || value.is_a?(Pito::Chat::Result::Error)
        end
      end
    end
  end
end
