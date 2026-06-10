# frozen_string_literal: true

# Handler for `unlink game <id> from video <id>` /
# `unlink video <id> from game <id>`.
#
# Free-chat: split on ` from ` (case-insensitive) into a left and right half.
# Each half begins with a noun discriminator (`game`/`games` or `video`/`videos`)
# followed by a numeric id (plain or with a leading `#`). Title refs are not
# supported — only local numeric ids. Connector word = `from`.
#
# Follow-up (detail card — singular video_id/game_id in payload):
#   Source is implied by the card entity.  Targets are parsed from everything
#   after the connector word `from`.  Comma or space separated, multi-target.
#   E.g. `unlink from 1,2` unlinks this video/game from games/videos 1 and 2.
#
# Follow-up (list card — video_ids/game_ids in payload):
#   Source id is on the LEFT of `from`; targets are on the RIGHT.
#   E.g. `unlink 17 from 1,2` unlinks video/game 17 from games/videos 1 and 2.
#
# Destroys the `VideoGameLink` join if present; missing link → gentle
# "already not linked" message (idempotent).
# The model's `after_commit` already enqueues game-stats refresh — not duplicated.
module Pito
  module Chat
    module Handlers
      class Unlink < Pito::Chat::Handler
        include MultiLinkHelpers

        self.verb = :unlink
        self.description_key = "pito.chat.unlink.descriptions.unlink"

        GAME_NOUNS  = %w[game games].freeze
        VIDEO_NOUNS = %w[video videos].freeze

        def call
          return follow_up_unlink if follow_up?

          raw = message.body_tokens.map(&:value).join(" ")
          parts = raw.split(/\bfrom\b/i, 2)

          return usage_hint if parts.size < 2

          left_words  = parts[0].strip.split
          right_words = parts[1].strip.split

          return usage_hint if left_words.empty? || right_words.empty?

          game, video = resolve_sides(left_words, right_words)
          return game  if result?(game)
          return video if result?(video)

          destroy_link(game, video)
        end

        private

        # ── Follow-up branch ───────────────────────────────────────────────────

        def follow_up_unlink
          if video_target?(VIDEO_NOUNS)
            follow_up_multi(
              connector:     "from",
              source_class:  ::Video,
              other_class:   ::Game,
              source_nouns:  VIDEO_NOUNS,
              other_nouns:   GAME_NOUNS,
              copy_ok:       "pito.copy.games.unlinked_multi",
              copy_op:       :unlink
            )
          else
            follow_up_multi(
              connector:     "from",
              source_class:  ::Game,
              other_class:   ::Video,
              source_nouns:  GAME_NOUNS,
              other_nouns:   VIDEO_NOUNS,
              copy_ok:       "pito.copy.games.unlinked_multi",
              copy_op:       :unlink
            )
          end
        end

        # ── Free-chat helpers ──────────────────────────────────────────────────

        def resolve_sides(left_words, right_words)
          left_noun  = left_words.first.downcase
          right_noun = right_words.first.downcase

          if GAME_NOUNS.include?(left_noun) && VIDEO_NOUNS.include?(right_noun)
            game  = resolve_game(left_words.drop(1))
            video = resolve_video(right_words.drop(1))
          elsif VIDEO_NOUNS.include?(left_noun) && GAME_NOUNS.include?(right_noun)
            video = resolve_video(left_words.drop(1))
            game  = resolve_game(right_words.drop(1))
          else
            return [ usage_hint, nil ]
          end

          [ game, video ]
        end

        def resolve_game(ref_words)
          ref = ref_words.join(" ").strip
          return usage_hint if ref.blank?

          id = ref.delete_prefix("#")
          return usage_hint unless id.match?(/\A\d+\z/)

          ::Game.find_by(id: id) || not_found_game(ref)
        end

        def resolve_video(ref_words)
          ref = ref_words.join(" ").strip
          return usage_hint if ref.blank?

          id = ref.delete_prefix("#")
          return usage_hint unless id.match?(/\A\d+\z/)

          ::Video.find_by(id: id) || not_found_video(ref)
        end

        # ── Shared helpers ─────────────────────────────────────────────────────

        def destroy_link(game, video)
          link = VideoGameLink.find_by(video: video, game: game)

          if link
            link.destroy!
            Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.unlinked", game: game.title, video: video.title) }
            ])
          else
            Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_linked", game: game.title, video: video.title) }
            ])
          end
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
            message_key:  "pito.chat.unlink.usage",
            message_args: {}
          )
        end

        # True when the value is a Chat::Result (Ok or Error) rather than a record.
        # Used to short-circuit after resolve_sides.
        def result?(value)
          value.is_a?(Pito::Chat::Result::Ok) || value.is_a?(Pito::Chat::Result::Error)
        end
      end
    end
  end
end
